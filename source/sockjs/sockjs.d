module sockjs.sockjs;

import vibe.d;
import std.stdio;
import std.string;
import std.regex;

///
public class Server
{
public:

	///
	this(SockJS.Options _options)
	{
		m_options = _options;
	}
	
	///
	public void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto url = req.requestURL;
		
		if(url.length >= m_options.prefix.length)
		{
			if(url[0..m_options.prefix.length] == m_options.prefix)
			{	
				munch(url, m_options.prefix);
				
				string[] elements = url.split("/");
				
				string _body = cast(string)req.bodyReader.readAll();
					
				handleSockJs(elements,_body,res,req.peer);
			}
		}
	}

	///
	private void handleSockJs(string[] _urlElements, string _body, HTTPServerResponse _res, string _remotePeer)
	{
		//writefln("handle: %s",_urlElements);

		_res.headers["Access-Control-Allow-Origin"] = "http://localhost:8080";
		_res.headers["Access-Control-Allow-Credentials"] = "true";
		_res.headers["Connection"] = "keep-alive";
		_res.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0";

		if(_urlElements.length == 1 && _urlElements[0] == "info")
		{
			_res.writeBody(q"{{"websocket":"false","origins":["*:*"],"cookie_needed":"false"}}","application/json; charset=UTF-8");
		}
		else if(_urlElements.length == 3)
		{
			string serverId = _urlElements[0];
			string userId = _urlElements[1];
			string method = _urlElements[2];

			if(userId in m_connections)
			{
				auto conn = m_connections[userId];

				conn.handleRequest(method == "xhr_send",_body,_res);
			}
			else
			{
				if(method == "xhr")
				{
					auto newConn = new Connection(&m_options, _remotePeer);
				
					m_onConnection(newConn);

					m_connections[userId] = newConn;

					_res.writeBody("o\n","application/javascript; charset=UTF-8");
				}
				else
					throw new Exception("wrong connect method");
			}
		}
		else
			throw new Exception("wrong param count");
	}

	///
	alias void delegate(Connection) EventOnConnection;

	///
	@property public void onConnection(EventOnConnection _callback) { m_onConnection = _callback; }
	
private:
	EventOnConnection	m_onConnection;
	SockJS.Options		m_options;
	Connection[string] 	m_connections;
}

///
public class Connection
{
public:

	///
	public this(SockJS.Options* _options, string _remotePeer)
	{
		m_remotePeer = _remotePeer;
		m_options = _options;
		m_timeoutMutex = new TaskMutex;
		m_pollCondition = new TaskCondition(m_timeoutMutex);
	}
	
	///
	public void write(string _msg)
	{
		m_outQueue ~= _msg;

		//debug writefln("emit");

		m_pollCondition.notifyAll();
	}
	
	///
	private void handleRequest(bool _send, string _body, HTTPServerResponse res)
	{
		if(!_send)
		{
			longPoll(res);
		}
		else
		{
			if(_body.length > 4)
			{
				auto arr = _body[2..$-2];

				foreach(e; splitter(arr, regex(q"{","}")))
					m_onData(e);
			}

			res.statusCode = 204;
			res.writeVoidBody();
		}
	}

	///
	private void longPoll(HTTPServerResponse res)
	{ 
		if(m_outQueue.length > 0)
		{
			flushQueue(res);
		}
		else
		{
			//debug writefln("long poll");

			synchronized(m_timeoutMutex)
				m_pollCondition.wait(m_options.heartbeat_delay.seconds);
		
			if(m_outQueue.length > 0)
			{
				//debug writefln("long poll signaled");

				flushQueue(res);
			}
			else
			{
				//debug writefln("heartbeat");

				res.writeBody("h\n");
			}
		}
	}
	
	///
	private void flushQueue(HTTPServerResponse res)
	{
		string outbody = "a[";

		foreach(s; m_outQueue)
			outbody ~= '"'~s~'"'~',';

		outbody = outbody[0..$-1];
		outbody ~= "]\n";

		//debug writefln("flush: '%s'",outbody);

		res.writeBody(outbody);

		m_outQueue.length = 0;
	}

	///
	alias void delegate() EventOnClose;
	///
	alias void delegate(string _msg) EventOnMsg;

	///
	@property public void onClose(EventOnClose _callback) { m_onClose = _callback; }
	///
	@property public void onData(EventOnMsg _callback) { m_onData = _callback; }

	///
	@property public const string remoteAddress() {return m_remotePeer;}

private:
	EventOnClose	m_onClose;
	EventOnMsg		m_onData;

	string			m_remotePeer;
	TaskMutex		m_timeoutMutex;
	TaskCondition	m_pollCondition;
	string[]		m_outQueue;
	SockJS.Options*	m_options;
}

///
struct SockJS
{
	///
	struct Options
	{
		string prefix;
		int heartbeat_delay = 25_000;
		int disconnect_delay = 5_000;
	}

	///
	public static Server createServer(Options _options)
	{
		return new Server(_options);
	}
}