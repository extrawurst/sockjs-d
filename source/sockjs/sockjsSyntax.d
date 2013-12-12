module sockjs.sockjsSyntax;

import vibe.d;

import sockjs.connection;

package struct SockJsSyntax
{
	package static
	{
		///
		void writeInfo(HTTPServerResponse _res)
		{
			_res.writeBody(q"{{"websocket":"false","origins":["*:*"],"cookie_needed":"false"}}","application/json; charset=UTF-8");
		}

		///
		void writeOpen(HTTPServerResponse _res)
		{
			_res.writeBody("o\n","application/javascript; charset=UTF-8");
		}

		///
		void writeHeartbeat(HTTPServerResponse _res)
		{
			_res.writeBody("h\n");
		}
	
		///
		void writeClose(HTTPServerResponse _res, Connection.CloseMsg _closeMsg)
		{
			_res.writeBody(format(q"{c[%s,"%s"]\n}", _closeMsg.code, _closeMsg.msg));
		}
	}
}