module sockjs.sockjs;

import vibe.d;
import std.stdio;
import std.string;
import std.regex;

public class Server
{
public:
	alias void delegate(Connection) EventOnConnection;

	this(SockJS.Options _options)
	{
		m_options = _options;
	}
	
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto url = req.requestURL;
		
		if(url.length >= m_options.prefix.length)
		{
			if(url[0..m_options.prefix.length] == m_options.prefix)
			{	
				munch(url, m_options.prefix);
				
				string[] elements = url.split("/");
				
				string _body = cast(string)req.bodyReader.readAll();
					
				handleSockJs(elements,_body,res);
			}
		}
	}
	
	private void handleSockJs(string[] _urlElements, string _body, HTTPServerResponse _res)
	{
		//writefln("handle: %s",_urlElements);

		_res.headers["Access-Control-Allow-Origin"] = "http://localhost:8080";
		_res.headers["Access-Control-Allow-Credentials"] = "true";
		_res.headers["Connection"] = "keep-alive";
		_res.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0";

		if(_urlElements.length == 1 && _urlElements[0] == "info")
		{
			_res.headers["Content-Type"] = "application/json; charset=UTF-8";
			_res.bodyWriter.write(q"{{"websocket":"false","origins":["*:*"],"cookie_needed":"false"}}");
			_res.bodyWriter.finalize();
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
					auto newConn = new Connection();
				
					OnConnection(newConn);

					m_connections[userId] = newConn;

					_res.headers["Content-Type"] = "application/javascript; charset=UTF-8";
					_res.bodyWriter.write("o");
					_res.bodyWriter.flush();
				}
				else
					throw new Exception("wrong connect method");
			}
		}
		else
			throw new Exception("wrong param count");
	}
	
//private:
	EventOnConnection OnConnection;
	
private:
	SockJS.Options		m_options;
	Connection[string] 	m_connections;
}

public class Connection
{
public:
	
	alias void delegate() EventOnClose;
	alias void delegate(string _msg) EventOnMsg;
	
	const string remoteAddress() {return "";}
	const int remotePort() {return 0;}

	public this()
	{
		m_timeoutMutex = new TaskMutex;
		m_pollCondition = new TaskCondition(m_timeoutMutex);
	}
	
	public void write(string _msg)
	{
		m_outQueue ~= _msg;

		writefln("emit");

		m_pollCondition.notifyAll();
	}
	
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
					OnData(e);
			}

			res.statusCode = 202;
			res.writeVoidBody();
		}
	}

	private void longPoll(HTTPServerResponse res)
	{ 
		if(m_outQueue.length > 0)
		{
			FlushQueue(res);
		}
		else
		{
			writefln("long poll");

			synchronized(m_timeoutMutex)
				m_pollCondition.wait(10.seconds);
		
			if(m_outQueue.length > 0)
			{
				writefln("long poll signaled");

				FlushQueue(res);
			}
			else
			{
				writefln("heartbeat");

				res.writeBody("h");
			}
		}
	}
	
	private void FlushQueue(HTTPServerResponse res)
	{
		string outbody = "a[";

		foreach(s; m_outQueue)
			outbody ~= '"'~s~'"'~',';

		outbody = outbody[0..$-1];
		outbody ~= ']';

		writefln("flush: '%s'",outbody);

		res.writeBody(outbody);

		m_outQueue.length = 0;
	}

//private:
	EventOnClose OnClose;
	EventOnMsg OnData;
private:
	TaskMutex m_timeoutMutex;
	TaskCondition m_pollCondition;
	string[] m_outQueue;
}
	
struct SockJS
{
	struct Options
	{
		string prefix;
		int heartbeat_delay = 25_000;
		int disconnect_delay = 5_000;
	}

	public static Server createServer(Options _options)
	{
		return new Server(_options);
	}
}