const net = require("net");

class Zookeeper {
  constructor(connectStr) {
    let servers;

    if (Array.isArray(connectStr)) {
      servers = connectStr;
    } else {
      servers = connectStr.split(",");
    }

    this.servers = servers.map(server => {
      if (typeof server === "object") {
        return server;
      }
      const [host, port] = server.split(":");
      return { host, port: parseInt(port) };
    });
  }

  async mntr(opts = {}) {
    const response = await this.flw("mntr", opts);  
    const entries = response
      .trim()
      .split("\n")
      .map((l) => {
        const [k, v] = l.split("\t");
        const numV = Number(v);
        return [k, isNaN(numV) ? v : numV];
      });

    return Object.fromEntries(entries);
  }

  async ruok(opts = {}) {
    const response = await this.flw("ruok", opts);
    return response.trim() === "imok";
  }

  flw(command, opts = {}) {
    const { serverIndex = 1, timeout = 5000 } = opts;
    const { host, port } = this.servers[serverIndex - 1];
    return new Promise((resolve, reject) => {
      const socket = net.createConnection(port, host);
      let data = "";

      socket.setTimeout(timeout);
      socket.on("connect", () => socket.write(command));
      socket.on("data", chunk => data += chunk);
      socket.on("end", () => resolve(data));
      socket.on("timeout", () => {
        socket.destroy();
        reject(new Error(`Timed out waiting for response to ${command}`));
      });
      socket.on("error", reject);
    });
  }
}

module.exports = Zookeeper;