module sockjs.connection;

import vibe.d;
import std.stdio;
import std.string;
import std.regex;
import std.array;

import sockjs.sockjs;
import sockjs.sockjsSyntax;

//version = simulatePollErrors;
//version = simulateSendErrors;

///
public class Connection
{
public:

	///
	this(Server _server, string _remotePeer, string _userId)
	{
		m_userId = _userId;
		m_remotePeer = _remotePeer;
		m_server = _server;
		m_queueMutex = new TaskMutex;
		m_timeoutMutex = new TaskMutex;
		m_pollCondition = new TaskCondition(m_timeoutMutex);

		m_timeoutTimer = getEventDriver().createTimer(&timeout);
		m_pollTimeout = getEventDriver().createTimer(&pollTimeout);
		m_closeTimer = getEventDriver().createTimer(&closeTimeout);

		resetTimeout();
	}

	///
	public void destroy()
	{
		m_timeoutTimer.stop();
		m_pollTimeout.stop();
		m_closeTimer.stop();
		
		m_userId = null;
		
		m_server = null;
		m_remotePeer = null;
		
		m_queueMutex = null;
		m_timeoutMutex = null;
		m_pollCondition = null;
	}

	///
	void write(string _msg)
	{
		if(isOpen)
		{
			synchronized(m_queueMutex)
				m_outQueue ~= _msg;

			//debug writefln("emit");

			m_pollCondition.notifyAll();
		}
	}

	///
	void close(int _code=0, string _msg="")
	{
		m_closeMsg.code = _code;
		m_closeMsg.msg = _msg;

		startClosing();
	}

	///
	alias void delegate() EventOnClose;
	///
	alias void delegate(string _msg) EventOnMsg;

	///
	@property void onClose(EventOnClose _callback) { m_onClose = _callback; }
	///
	@property void onData(EventOnMsg _callback) { m_onData = _callback; }

	///
	@property const string userId() { return m_userId; }
	///
	@property const string remoteAddress() { return m_remotePeer; }
	///
	@property const bool isOpen() { return m_state == State.Open; }

	///
	@property string protocol() { return "xhr-polling"; }

	///
	package @property CloseMsg closeMsg() const { return m_closeMsg; }

private:

	///
	void flushQueue(HTTPServerResponse res)
	{
		auto buffer = appender("a[");

		string[] outQueue;

		synchronized(m_queueMutex)
		{
			outQueue = m_outQueue.dup;
			m_outQueue.length = 0;
		}

		foreach(s; outQueue)
		{
			buffer ~= '"';
			buffer ~= s;
			buffer ~= "\",";
		}

		string outbody = buffer.data;
		outbody = outbody[0..$-1];
		outbody ~= "]\n";

		//debug writefln("flush: '%s'",outbody);

		res.writeBody(outbody);
	}

	///
	void timeout()
	{
		m_onClose();

		m_timeoutTimer.stop();

		startClosing();
	}

	void startClosing()
	{
		m_state = State.Closing;

		if(m_server !is null)
			m_closeTimer.rearm(m_server.options.connection_blocking.msecs);

		if(m_pollCondition !is null)
			m_pollCondition.notifyAll();
	}

	///
	void longPoll(HTTPServerResponse res)
	{
		version(simulatePollErrors)
		{
			static int pollCount=0;

			pollCount++;

			debug writefln("pollcount: %s",pollCount);

			if(pollCount % 3 == 0)
			{
				debug writefln("SIMULATE POLL ERROR");

				throw new SockJsException("simulate packet loss");
			}
		}

		scope(exit) resetTimeout();

		m_timeoutTimer.stop();

		if(isDataPending)
		{
			flushQueue(res);
		}
		else
		{
			m_pollTimeout.rearm(m_server.options.heartbeat_delay.msecs);

			synchronized(m_timeoutMutex) m_pollCondition.wait();

			m_pollTimeout.stop();

			if(m_state == State.Closing || m_state == State.Closed)
			{
				try SockJsSyntax.writeClose(res, m_closeMsg);
				catch(Throwable e)
				{
					logError("closing error: %s",e);
				}
			}
			else
			{
				if(isDataPending)
				{
					//debug writefln("long poll signaled");

					flushQueue(res);
				}
				else
				{
					SockJsSyntax.writeHeartbeat(res);
				}
			}
		}
	}

	///
	void resetTimeout()
	{
		if(m_timeoutTimer !is null &&
		   m_server !is null)
			m_timeoutTimer.rearm(m_server.options.disconnect_delay.msecs);
	}

	///
	void pollTimeout()
	{
		if(m_pollCondition !is null)
			m_pollCondition.notifyAll();
	}

	///
	void closeTimeout()
	{
		if(m_server !is null)
			m_server.connectionClosed(this);
	}

	///
	@property const bool isDataPending() {synchronized(m_queueMutex){return m_outQueue.length > 0;}}

	///
	package void handleRequest(bool _send, string _body, HTTPServerResponse res)
	{
		if(!_send)
		{
			longPoll(res);
		}
		else
		{
			version(simulateSendErrors)
			{
				static int sendCount=0;

				sendCount++;

				debug writefln("sendcount: %s",sendCount);

				if(sendCount % 3 == 0)
				{
					debug writefln("SIMULATE SEND ERROR");

					throw new Exception("simulate packet loss");
				}
			}

			res.statusCode = 404;

			scope(exit) res.writeBody("");

			if(isOpen)
			{
				scope(success) res.statusCode = 204;

				if(_body.length > 4)
				{
					auto arr = _body[2..$-2];

					foreach(e; splitter(arr, regex(q"{","}")))
						m_onData(e);
				}
			}
		}
	}

private:

	public struct CloseMsg
	{
		int		code;
		string	msg;
	}

	enum State
	{
		Open,
		Closing,
		Closed,
	}

	EventOnClose	m_onClose;
	EventOnMsg		m_onData;

	string			m_userId;
	string			m_remotePeer;
	TaskMutex		m_timeoutMutex;
	TaskMutex		m_queueMutex;
	TaskCondition	m_pollCondition;
	string[]		m_outQueue;
	Server			m_server;
	State			m_state = State.Open;
	CloseMsg		m_closeMsg;
	Timer			m_timeoutTimer;
	Timer			m_pollTimeout;
	Timer			m_closeTimer;
}
