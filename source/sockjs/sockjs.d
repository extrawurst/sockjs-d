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
		
		m_connections["foo"] = new Connection();
	}
	
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto url = req.url;
		
		if(url.length >= m_options.prefix.length)
		{
			if(url[0..m_options.prefix.length] == m_options.prefix)
			{
				if(req.method == HTTPMethod.POST)
				{
				}
				
				munch(url, m_options.prefix);
				
				string[] elements = url.split("/");
				
				string _body = cast(string)req.bodyReader.readAll();
					
				handleSockJs(elements,_body,res);
				
				//writefln("req to sockjs: %s",url);
				//
				//m_connections["foo"].longPoll(req,res);
			}
			else
			{
				//writefln("long poll quit");
			    //
				//m_connections["foo"].write(url);
			}
		}
	}
	
	private void handleSockJs(string[] _urlElements, string _body, HTTPServerResponse _res)
	{
		writefln("body: %s", _body);
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
	
	this()
	{
		m_pollSignal = getEventDriver().createManualEvent();
	}
	
	void write(string _msg)
	{
		m_outQueue ~= _msg;
		
		m_pollSignal.emit();
	}
	
	void longPoll(HTTPServerRequest req, HTTPServerResponse res)
	{
		m_outQueue.length = 0;
		
		// if data
		// -> reply
		// start timer
		// 
		m_pollSignal.wait(dur!"seconds"(10), m_pollSignal.emitCount);
		
		if(m_outQueue.length > 0)
		{
			res.writeBody(m_outQueue[0],"");
			
			m_outQueue = m_outQueue[1..$];
		}
		else
			res.writeBody("heartbeat","");
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