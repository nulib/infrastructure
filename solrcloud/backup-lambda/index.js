const {
  SecretsManagerClient,
  GetSecretValueCommand
} = require("@aws-sdk/client-secrets-manager");
const { format } = require("date-and-time");
const SolrCluster = require("./solr_cluster");
const Zookeeper = require("./zookeeper");
const Honeybadger = require("@honeybadger-io/js");
const { HONEYBADGER_API_KEY, HONEYBADGER_CHECKIN_ID, HONEYBADGER_ENV } =
  process.env;

Honeybadger.configure({
  apiKey: HONEYBADGER_API_KEY,
  environment: HONEYBADGER_ENV
});

let solrCluster;
let zk;

const initialize = async () => {
  if (solrCluster && zk) return;
  const secretsClient = new SecretsManagerClient({});
  const SecretId = `${process.env.SECRETS_PATH}/infrastructure/solrcloud`;
  const { SecretString } = await secretsClient.send(
    new GetSecretValueCommand({ SecretId })
  );
  const { solr_url, zookeeper_servers } = JSON.parse(SecretString);
  solrCluster = new SolrCluster(solr_url);
  zk = new Zookeeper(zookeeper_servers);
};

const handler = async (event, _context) => {
  await initialize();
  switch (event.operation) {
    case "solr:backup":
      const result = await solrBackup(event);
      if (HONEYBADGER_CHECKIN_ID) {
        await Honeybadger.checkIn(HONEYBADGER_CHECKIN_ID);
      }
      return result;
    case "solr:list":
      return await solrList(event);
    case "solr:restore":
      return await solrRestore(event);
    case "solr:ready":
      return await solrReady(event);
    case "zookeeper:ready":
      return await zkReady(event);
    case "set-log-level":
      return await setLogLevel(event);
  }
};

const setLogLevel = async (event) => {
  return await solrCluster.setLogLevel(event.level);
};

const solrList = async (event) => {
  return await solrCluster.listBackups(event.name);
};

const solrBackup = async (event) => {
  if (event.collection) {
    return await solrCluster.backup(event.collection);
  } else if (event.collections) {
    return await backupMultiple(event.collections);
  } else {
    const state = await solrCluster.status();
    const collections = Object.keys(state.cluster.collections);
    return await backupMultiple(collections);
  }
};

const backupMultiple = async (collections) => {
  const result = {};
  for (const collection of collections) {
    result[collection] = await solrCluster.backup(collection);
  }
  return result;
};

const solrRestore = async (event) => {
  const collection = event.collection;
  const name = event.name || collection;
  const failIfExists = event.failIfExists === true;
  const prune = event.prune !== false;
  const backupId = event.backupId;

  return await solrCluster.restore(collection, name, {
    backupId,
    failIfExists,
    prune
  });
};

const solrReady = async (event) => {
  try {
    const desiredNodes = Number(event.solr.nodeCount);
    const liveNodes = await solrCluster.liveNodeCount();
    return liveNodes == desiredNodes;
  } catch (err) {
    console.error(err.code, err.reason);
    return false;
  }
};

const zkReady = async (event) => {
  try {
    const desiredNodes = Number(event.zookeeper.nodeCount);
    const state = await zk.mntr();
    return desiredNodes == state.zk_quorum_size;
  } catch (err) {
    console.error(err.code, err.reason);
    return false;
  }
};

module.exports = { handler: Honeybadger.lambdaHandler(handler) };
