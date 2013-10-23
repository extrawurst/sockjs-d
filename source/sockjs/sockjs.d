module sockjs.sockjs;

import vibe.d;
import std.stdio;
import std.string;

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
		auto url = req.url;
		
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
		writefln("handle: ",_urlElements);

		if(_urlElements.length == 1 && _urlElements[0] == "info")
		{
			_res.headers["access-control-allow-origin"] = "*";
			_res.headers["access-control-allow-credentials"] = "false";

			_res.writeJsonBody(q"{{"websocket":"false","origins":["*:*"],"cookie_needed":"false"}}");
		}
		else if(_urlElements.length == 3)
		{
			string serverId = _urlElements[0];
			string userId = _urlElements[1];
			string method = _urlElements[2];

			if(userId in m_connections)
			{
				writefln("got: ",method);

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

					_res.writeBody("o");
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
		m_pollSignal = getEventDriver().createManualEvent();
	}
	
	public void write(string _msg)
	{
		m_outQueue ~= _msg;
		
		m_pollSignal.emit();
	}
	
	private void handleRequest(bool _send, string _body, HTTPServerResponse res)
	{
		if(!_send)
		{
			longPoll(res);
		}
		else
		{
			//TODO: parse json
			OnData(_body);
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

			m_pollSignal.wait(dur!"seconds"(10), m_pollSignal.emitCount);
		
			if(m_outQueue.length > 0)
			{
				FlushQueue(res);
			}
			else
				res.writeBody("h");
		}
	}
	
	private void FlushQueue(HTTPServerResponse res)
	{
		string outbody = "[";

		foreach(s; m_outQueue)
			outbody ~= '"'~s~'"'~',';

		outbody = outbody[0..$-1];
		outbody ~= ']';

		writefln("flush: '%s'",outbody);

		res.writeBody(outbody,"");

		m_outQueue.length = 0;
	}

//private:
	EventOnClose OnClose;
	EventOnMsg OnData;
private:
	ManualEvent m_pollSignal;
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