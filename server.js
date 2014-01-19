var Express = require("express");
var Server = Express();
Server.use(Express.static("static"));
Server.listen(8090);
