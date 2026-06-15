import { createApp } from "./app.js";
import { loadConfig } from "./config.js";

const config = loadConfig();
const server = createApp(config);

server.listen(config.port, "0.0.0.0", () => {
  console.log(`Character Brain server listening on port ${config.port}`);
});
