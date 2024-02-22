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

const createModelGroup = async (namespace) => {
  const name = `${namespace}-model-group`;

  try {
    const result = await fetch({
      path: "_plugins/_ml/model_groups/_search",
      body: JSON.stringify({
        query: {
          term: {
            "name.keyword": {
              value: name
            }
          }
        }
      })
    });

    if (result?.hits?.total?.value == 1) {
      return { model_id: result.hits.hits[0]._id };
    }
  } catch (err) {
    if (err.name != "DeployError") {
      throw err;
    }
  }

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

const handler = async (event) => {
  try {
    const { model_group_id } = await createModelGroup(event.namespace);
    const { connector_id } = await createConnector(event.connector_spec);
    const { model_id } = await createModel(
      event.model_name,
      event.model_version,
      model_group_id,
      connector_id
    );
    return {
      statusCode: 200,
      body: JSON.stringify({ model_id })
    };
  } catch (err) {
    return err;
  }
};

module.exports = { handler };
