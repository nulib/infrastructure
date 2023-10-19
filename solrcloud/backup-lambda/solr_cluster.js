const axios = require('axios').default;
const { URLSearchParams } = require('url');

const defaultBackupLocation = '/data/backup';
const defaultBackupRetention = 14;

class SolrCluster {
  #client

  constructor(baseURL) {
    this.#client = axios.create({ baseURL });
  }

  async status(params) {
    return await this.#request('CLUSTERSTATUS', params || {})
  }

  async liveNodeCount() {
    const state = await this.status();
    return state.cluster.live_nodes.length;
  }

  async backup(collection, name) {
    console.log(`Backing up ${collection} to ${name}`);
    const location = process.env.SOLR_BACKUP_LOCATION || defaultBackupLocation;
    const maxNumBackupPoints = process.env.SOLR_BACKUP_RETENTION || defaultBackupRetention;
    if (!name) name = collection;
    return await this.#request('BACKUP', { collection, name, location, maxNumBackupPoints });
  }

  async listBackups(name) {
    const location = process.env.SOLR_BACKUP_LOCATION || defaultBackupLocation;
    return await this.#request('LISTBACKUP', { name, location });
  }

  async restore(collection, name, options) {
    if (name === undefined) name = collection;
    if (options === undefined) options = { failIfExists: true }
    let { backupId, failIfExists } = options;
    failIfExists = !!failIfExists;

    if (!failIfExists) {
      const state = await this.status();
      if (collection in state.cluster.collections) {
        console.warn(`Collection ${collection} exists. Ignoring.`);
        return true;
      }
    }

    console.log(`Restoring ${collection} from ${name}:${backupId || 'LATEST'}`);
    
    const location = process.env.SOLR_BACKUP_LOCATION || defaultBackupLocation;
    return await this.#request('RESTORE', { collection, name, location, backupId });
  }

  async deleteDeadReplicas(collection, shard) {
    if (!shard) shard = 'shard1';
    const state = await this.status({ collection });
    const collectionState = state.cluster.collections[collection];
    const replicas = collectionState.shards[shard].replicas;
    for (const replica in replicas) {
      if (replicas[replica].state == 'down') {
        console.info(`Deleting dead replica ${collection}.${shard}.${replica}`);
        await this.#request('DELETEREPLICA', { collection, shard, replica });
      }
    }
  }

  async addReplicas(collection, shard) {
    if (!shard) shard = 'shard1';
    const state = await this.status({ collection });
    const collectionState = state.cluster.collections[collection];
    const replicas = collectionState.shards[shard].replicas;
    const desiredCount = Number(collectionState.replicationFactor);
    const liveNodeCount = state.cluster.live_nodes.length;
    const toAdd = Math.min(desiredCount, liveNodeCount) - Object.keys(replicas).length;
    console.info(`Adding ${toAdd} replicas to ${collection}.${shard}`);
    for (let i = 1; i <= toAdd; i++) {
      await this.#request('ADDREPLICA', { collection, shard });
    }
  }

  async redistributeShard(collection, shard) {
    await this.deleteDeadReplicas(collection, shard);
    await this.addReplicas(collection, shard);
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
    const response = await this.#client.get(url);
    if (response.status < 300) {
      return response.data;
    }
    return response;
  }
}

module.exports = SolrCluster;