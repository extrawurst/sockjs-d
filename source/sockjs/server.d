module sockjs.server;

import std.stdio;

import vibe.d;
import sockjs.sockjs:SockJS;
import sockjs.connection;
import sockjs.sockjsSyntax;

///
class SockJsException : Exception
{
	///
	public this(string _s)
	{
		super(_s);
	}
}

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
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
	{
		scope(failure) logCritical("handle request failed");

		auto url = req.requestURL;

		if(url.length >= m_options.prefix.length)
		{
			if(url[0..m_options.prefix.length] == m_options.prefix)
			{	
				munch(url, m_options.prefix);

				string[] elements = url.split("/");

				string _body = cast(string)req.bodyReader.readAll();

				try handleSockJs(elements,_body,res,req.peer);
				catch(SockJsException e)
				{
					logError("handleSockJs failed: %s",e);

					res.statusCode = 404;
					res.writeBody("");
				}
			}
		}
	}

	///
	alias void delegate(Connection) EventOnConnection;

	///
	@property void onConnection(EventOnConnection _callback) { m_onConnection = _callback; }

	///
	@property const(SockJS.Options)* options() const { return &m_options; }

private:
	EventOnConnection	m_onConnection;
	SockJS.Options		m_options;
	Connection[string] 	m_connections;

	///
	void handleSockJs(string[] _urlElements, string _body, HTTPServerResponse _res, string _remotePeer)
	{
		//writefln("handle: %s",_urlElements);

		//TODO: cleanup
		_res.headers["Access-Control-Allow-Origin"] = "http://localhost:8080";
		_res.headers["Access-Control-Allow-Credentials"] = "true";
		_res.headers["Connection"] = "keep-alive";
		_res.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0";

		if(_urlElements.length == 1 && _urlElements[0] == "info")
		{
			SockJsSyntax.writeInfo(_res);
		}
		else if(_urlElements.length == 3)
		{
			string serverId = _urlElements[0];
			string userId = _urlElements[1];
			string method = _urlElements[2];

			if(userId in m_connections)
			{
				auto conn = m_connections[userId];

				if(conn.isOpen)
					conn.handleRequest(method == "xhr_send",_body,_res);
				else
					SockJsSyntax.writeClose(_res, conn.closeMsg);
			}
			else
			{
				if(method != "xhr")
					throw new SockJsException("wrong connect method");
				else
				{
					auto newConn = new Connection(this, _remotePeer, userId);

					m_onConnection(newConn);

					m_connections[userId] = newConn;

					//logInfo("[sockjs] new connection (count: %s)",m_connections.length);

					SockJsSyntax.writeOpen(_res);
				}
			}
		}
		else
			throw new SockJsException("wrong param count");
	}

	///
	package void connectionClosed(Connection _conn)
	{

		if(_conn.userId in m_connections)
		{
			m_connections.remove(_conn.userId);

			//logInfo("[sockjs] closed connection (count: %s)",m_connections.length);
		}

		_conn.destroy();
	}
}
