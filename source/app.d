import vibe.d;
import sockjs.sockjs;
import std.stdio;

void logRequest(HTTPServerRequest req, HTTPServerResponse res)
{
	writefln("url: '%s' peer: '%s' method: '%s'", req.requestURL, req.peer, req.method);
}

static this()
{
	SockJS.Options options;
	options.prefix = "/echo/";
	auto sjs = SockJS.createServer(options);

	auto router = new URLRouter;
		router
		.any("/index.html", vibe.http.fileserver.serveStaticFile("index.html",new HTTPFileServerSettings()))
		.any("/sockjs.js", vibe.http.fileserver.serveStaticFile("sockjs.js",new HTTPFileServerSettings()))
		.any("*", &logRequest)
		.any("*", &sjs.handleRequest);
	
	sjs.onConnection = (Connection conn) {
		writefln("new conn: %s", conn.remoteAddress);
		
		conn.onData = (string message) {
		
			writefln("msg: %s", message);
			
			conn.write(message);
		};
		
		conn.onClose = () {
			writefln("closed conn: %s", conn.remoteAddress);
		};
	};
	
	auto settings = new HTTPServerSettings;
	settings.port = 8989;
	listenHTTP(settings, router);
}