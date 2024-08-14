const { HttpRequest } = require("@smithy/protocol-http");
const { awsFetch } = require("./aws-fetch");
const { OPENSEARCH_ENDPOINT } = process.env;

class DeployError extends Error {
  constructor(statusCode, message) {
    super(message);
    this.statusCode = statusCode;
    this.body = message;
    this.name = "DeployError";
  }
}

const fetch = async (params) => {
  const request = new HttpRequest({
    method: "POST",
    hostname: OPENSEARCH_ENDPOINT,
    headers: {
      Host: OPENSEARCH_ENDPOINT,
      "Content-Type": "application/json"
    },
    ...params
  });

  const response = await awsFetch(request);
  const { statusCode, body } = response;
  if (statusCode >= 200 && statusCode <= 299) {
    return JSON.parse(body);
  } else {
    throw new DeployError(statusCode, body);
  }
};

const findExisting = async (type, terms) => {
  const query = { bool: { must: [] } };

  for (const term in terms) {
    const clause = { term: {} };
    const field = `${term}.keyword`;
    clause.term[field] = { value: terms[term] };
    query.bool.must.push(clause);
  }

  try {
    const result = await fetch({
      path: `_plugins/_ml/${type}s/_search`,
      body: JSON.stringify({ query })
    });

    if (result?.hits?.total?.value == 1) {
      return result.hits.hits[0]._id;
    }
  } catch (err) {
    if (err.name != "DeployError") throw err;
    return null;
  }
};

const createModelGroup = async (namespace) => {
  const name = `${namespace}-model-group`;

  const model_group_id = await findExisting("model_group", { name: name });
  if (model_group_id) return { model_group_id };

  return await fetch({
    path: "_plugins/_ml/model_groups/_register",
    body: JSON.stringify({
      name,
      description: `A machine learning model group for the ${namespace} namespace`
    })
  });
};

const createConnector = async (connector_spec) => {
  return await fetch({
    path: "_plugins/_ml/connectors/_create",
    body: JSON.stringify(connector_spec)
  });
};

const updateConnector = async (connector_spec) => {
  connector_id = await findExisting("connector", { name: connector_spec.name });
  if (!connector_id) {
    console.warn(`No existing connector named ${connector_spec.name}`);
    return null;
  }
  model_id = await findExisting("model", { connector_id });
  if (model_id) {
    await undeployModel(model_id);
  }
  const result = await fetch({
    method: "PUT",
    path: `_plugins/_ml/connectors/${connector_id}`,
    body: JSON.stringify(connector_spec)
  });
  if (model_id) {
    await deployModel(model_id);
  }
  return { model_id };
};

const createModel = async (name, version, model_group_id, connector_id) => {
  return await fetch({
    path: "_plugins/_ml/models/_register",
    query: { deploy: "true" },
    body: JSON.stringify({
      name,
      version,
      model_group_id,
      connector_id,
      function_name: "remote",
      model_format: "TORCH_SCRIPT"
    })
  });
};

const deployModel = async (model_id) => {
  return await fetch({
    method: "POST",
    path: `_plugins/_ml/models/${model_id}/_deploy`
  });
};

const undeployModel = async (model_id) => {
  return await fetch({
    method: "POST",
    path: `_plugins/_ml/models/${model_id}/_undeploy`
  });
};

const create = async (event) => {
  const { model_group_id } = await createModelGroup(event.namespace);
  const { connector_id } = await createConnector(event.connector_spec);
  const { model_id } = await createModel(
    event.model_name,
    event.model_version,
    model_group_id,
    connector_id
  );
  return { model_id };
};

const destroy = async (event) => {
  let connector_id, model_id;
  try {
    connector_id = await findExisting("connector", {
      name: event.connector_spec.name
    });
    if (connector_id) {
      model_id = await findExisting("model", { connector_id });
      if (model_id) {
        await fetch({
          method: "POST",
          path: `_plugins/_ml/models/${model_id}/_undeploy`
        });
        await fetch({
          method: "DELETE",
          path: `_plugins/_ml/models/${model_id}`
        });
      }
      await fetch({
        method: "DELETE",
        path: `_plugins/_ml/connectors/${connector_id}`
      });
    }
  } catch (err) {}
  return { connector_id, model_id };
};

const update = async (event) => {
  return await updateConnector(event.connector_spec);
};

const handler = async (event) => {
  try {
    let body;
    console.log("Handling", event.tf.action, "event");
    switch (event.tf.action) {
      case "create":
        body = await create(event);
        break;
      case "update":
        body = await update(event);
        break;
      case "delete":
        body = await destroy(event);
        break;
    }
    return { statusCode: 200, body: JSON.stringify(body) };
  } catch (err) {
    return err;
  }
};

module.exports = {
  handler,
  findExisting,
  deployModel,
  undeployModel,
  updateConnector
};
