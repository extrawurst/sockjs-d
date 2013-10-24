module sockjs.connection;

import vibe.d;
import std.stdio;
import std.string;
import std.regex;

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

	void close(int _code, string _msg)
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

private:

	///
	void flushQueue(HTTPServerResponse res)
	{
		//TODO: use lock for queue

		string outbody = "a[";

		foreach(s; m_outQueue)
			outbody ~= '"'~s~'"'~',';

		outbody = outbody[0..$-1];
		outbody ~= "]\n";

		//debug writefln("flush: '%s'",outbody);

		res.writeBody(outbody);

		synchronized(m_queueMutex)
			m_outQueue.length = 0;
	}

	///
	void longPoll(HTTPServerResponse res)
	{
		if(isDataPending)
		{
			flushQueue(res);
		}
		else
		{
			//debug writefln("long poll");

			synchronized(m_timeoutMutex)
				m_pollCondition.wait(m_options.heartbeat_delay.seconds);

			if(m_state == State.Closing)
			{
				//TODO: use format
				res.writeBody("c["~ to!string(m_closeMsg.code) ~",\""~m_closeMsg.msg~"\"]\n");
			}
			else
			{
				//TODO: use lock for queue
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
}
