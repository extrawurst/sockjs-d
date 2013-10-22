import vibe.d;
import sockjs.sockjs;
import std.stdio;

void logRequest(HTTPServerRequest req, HTTPServerResponse res)
{
	writefln("url: '%s' peer: '%s' method: '%s' host: '%s'", req.url, req.peer, req.method, req.host);
}

static this()
{
	SockJS.Options options;
	options.prefix = "/echo/";
	auto sjs = SockJS.createServer(options);

	auto router = new URLRouter;
		router
		.any("*", &logRequest)
		.any("*", &sjs.handleRequest);
	
	sjs.OnConnection = (Connection conn) {
		writefln("new conn: ", conn.remoteAddress);
		
		conn.OnData = (string message) {
		
			writefln("msg: ", message);
			
			conn.write(message);
		};
		
		conn.OnClose = () {
			writefln("closed conn: ", conn.remoteAddress);
		};
		
	};
	
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	listenHTTP(settings, router);
}