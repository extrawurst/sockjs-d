module sockjs.sockjs;

public import sockjs.server;
public import sockjs.connection;

///
struct SockJS
{
	///
	struct Options
	{
		string prefix;
		int heartbeat_delay = 25_000;
		int disconnect_delay = 5_000;
		int connection_blocking = 20_000;
	}

	///
	static Server createServer(Options _options)
	{
		return new Server(_options);
	}
}
