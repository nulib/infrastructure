const axios = require("axios").default;
const { URLSearchParams } = require("url");

const location = process.env.SOLR_BACKUP_LOCATION || "solr";
const maxNumBackupPoints = process.env.SOLR_BACKUP_RETENTION || 7;

class SolrCluster {
  #client;

  constructor(baseURL) {
    this.#client = axios.create({ baseURL });
  }

  async status(params) {
    return await this.#request("CLUSTERSTATUS", params || {});
  }

  async liveNodeCount() {
    const state = await this.status();
    return state.cluster.live_nodes.length;
  }

  async backup(collection, name) {
    if (!name) name = collection;
    console.log(`Backing up ${collection} to ${name}`);
    return await this.#request("BACKUP", {
      collection,
      name,
      location,
      maxNumBackupPoints
    });
  }

  async listBackups(name) {
    return await this.#request("LISTBACKUP", { name, location });
  }

  async findLatestBackup(name) {
    const { backups } = await this.listBackups(name);
    if (!backups || backups.length === 0) return null;
    return (
      backups.reduce((latest, backup) => {
        return !latest || backup.startTime > latest.startTime ? backup : latest;
      }, null) || {}
    );
  }

  async pruneCollection(collection, opts = {}) {
    console.log(`Pruning ${collection}`);
    const { liveReplicas } = await this.deleteDeadReplicas(collection);
    console.log(liveReplicas);
    if (liveReplicas.length > 0) {
      await this.addReplicas(collection, opts);
    } else if (opts.deleteIfEmpty) {
      console.warn(`No live replicas for ${collection}. Deleting collection.`);
      await this.deleteCollection(collection);
    } else {
      console.warn(`No live replicas for ${collection}. Leaving it alone.`);
    }
  }

  async restore(
    collection,
    name,
    options = { failIfExists: true, prune: true }
  ) {
    if (name === undefined) name = collection;
    let { backupId, failIfExists, prune } = options;
    failIfExists = !!failIfExists;
    prune = !!prune;

    if (prune) {
      await this.pruneCollection(collection, { deleteIfEmpty: true });
    }

    if (!backupId) {
      ({ backupId } = await this.findLatestBackup(name));
    }

    if (!failIfExists) {
      const state = await this.status();
      if (collection in state.cluster.collections) {
        console.warn(`Collection ${collection} exists. Ignoring.`);
        return true;
      }
    }

    console.log(`Restoring ${collection} from ${name}:${backupId || "LATEST"}`);

    return await this.#request("RESTORE", {
      collection,
      name,
      location,
      backupId
    });
  }

  async deleteDeadReplicas(collection, opts = {}) {
    const shard = opts.shard || "shard1";
    const state = await this.status({ collection });
    const collectionState = state?.cluster?.collections?.[collection];
    if (!collectionState) return { collection, liveReplicas: [], deletedReplicas: [] };
    const replicas = collectionState?.shards?.[shard]?.replicas;
    if (!replicas) return { collection, liveReplicas: [], deletedReplicas: [] };
    const liveNodes = new Set(state.cluster.live_nodes);
    const deletedReplicas = [];
    for (const replica in replicas) {
      if (!liveNodes.has(replicas[replica].node_name)) {
        console.info(`Deleting dead replica ${collection}.${shard}.${replica}`);
        await this.#request("DELETEREPLICA", { collection, shard, replica });
        deletedReplicas.push(replica);
      }
    }
    const liveReplicas = Object.entries(replicas)
      .filter(([_, r]) => liveNodes.has(r.node_name))
      .map(([name, _]) => name);
    return { collection, liveReplicas, deletedReplicas };
  }

  async addReplicas(collection, opts = {}) {
    const shard = opts.shard || "shard1";
    const state = await this.status({ collection });
    const collectionState = state.cluster.collections[collection];
    const replicas = collectionState.shards[shard].replicas;
    if (opts.node) {
      const onNode = Object.values(replicas).some((r) => r.node_name === opts.node && r.state !== "down");
      if (onNode) {
        console.info(`${collection}.${shard} already has a replica on ${opts.node}`);
      } else {
        console.info(`Adding a replica of ${collection}.${shard} on ${opts.node}`);
        await this.#request("ADDREPLICA", { collection, shard, node: opts.node });
      }
      return;
    }
    const liveNodeCount = state.cluster.live_nodes.length;
    const desiredCount = opts.expand ? liveNodeCount : Number(collectionState.replicationFactor);
    const toAdd =
      Math.min(desiredCount, liveNodeCount) - Object.keys(replicas).length;
    console.info(`Adding ${toAdd} replicas to ${collection}.${shard}`);
    for (let i = 1; i <= toAdd; i++) {
      await this.#request("ADDREPLICA", { collection, shard });
    }
  }

  async redistributeShard(collection, opts = {}) {
    await this.deleteDeadReplicas(collection, opts);
    await this.addReplicas(collection, opts);
  }

  async deleteCollection(collection) {
    try {
      await this.#request("DELETE", { name: collection });
    } catch (error) {
      // noop
    }
  }

  #logError(error) {
    if (error?.response) {
      const { status, statusText, data } = error.response;
      console.error(`${status}: ${statusText}`);
      if (data) {
        console.error(JSON.stringify(data));
      }
    } else {
      console.error(error);
    }
  }

  async #request(action, params) {
    for (const key in params) {
      if (params[key] === undefined || params[key] === null) {
        delete params[key];
      }
    }
    const query = new URLSearchParams(params).toString();
    const url = `/admin/collections?action=${action}&${query}`;
    console.log(`Requesting ${url}`);
    try {
      const response = await this.#client.get(url);
      if (response.status < 300) {
        return response.data;
      }
      return response;
    } catch (error) {
      this.#logError(error);
      throw error;
    }
  }
}

module.exports = SolrCluster;
