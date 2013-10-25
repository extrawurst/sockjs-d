module sockjs.connection;

import vibe.d;
import std.stdio;
import std.string;
import std.regex;
import std.array;

import sockjs.sockjs;

///
public class Connection
{
public:

	///
	this(SockJS.Options* _options, string _remotePeer)
	{
		m_remotePeer = _remotePeer;
		m_options = _options;
		m_queueMutex = new TaskMutex;
		m_timeoutMutex = new TaskMutex;
		m_pollCondition = new TaskCondition(m_timeoutMutex);

		m_timeoutTimer = getEventDriver().createTimer(&timeout);
		m_pollTimeout = getEventDriver().createTimer(&pollTimeout);

		resetTimeout();
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

		m_state = State.Closing;

		m_pollCondition.notifyAll();
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
	@property const string remoteAddress() {return m_remotePeer;}
	///
	@property bool isOpen() { return m_state == State.Open; }

	///
	@property string protocol() { return "xhr-polling"; }

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

		m_state = State.Closing;
	}

	///
	void longPoll(HTTPServerResponse res)
	{
		scope(exit) resetTimeout();

		m_timeoutTimer.stop();

		if(isDataPending)
		{
			flushQueue(res);
		}
		else
		{
			m_pollTimeout.rearm(m_options.heartbeat_delay.msecs);
			
			synchronized(m_timeoutMutex) m_pollCondition.wait();

			m_pollTimeout.stop();

			if(m_state == State.Closing)
			{
				try{
					res.writeBody(format(q"{c[%s,"%s"]\n}", m_closeMsg.code, m_closeMsg.msg));
				}
				catch(Throwable e)
				{
					debug writefln("closing error: %s",e);
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
					//debug writefln("heartbeat");

					res.writeBody("h\n");
				}
			}
		}
	}

	///
	void resetTimeout()
	{
		m_timeoutTimer.rearm(m_options.disconnect_delay.msecs);
	}

	///
	void pollTimeout()
	{
		m_pollCondition.notifyAll();
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

private:
	struct CloseMsg
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

	string			m_remotePeer;
	TaskMutex		m_timeoutMutex;
	TaskMutex		m_queueMutex;
	TaskCondition	m_pollCondition;
	string[]		m_outQueue;
	SockJS.Options*	m_options;
	State			m_state = State.Open;
	CloseMsg		m_closeMsg;
	Timer			m_timeoutTimer;
	Timer			m_pollTimeout;
}
