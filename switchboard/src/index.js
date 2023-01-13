var responseStatus = ${response_status};
var mappings = ${mappings};

var statusCodeDescriptions = {
  301: "Moved Permanently",
  302: "Found"
}

function pathPlusQuery(event) {
  var path = event.request.uri.replace(/^\/*/, "");
  if (Object.keys(event.request.querystring).length == 0) {
    return path;
  }

  var query = [];
  for (var key in event.request.querystring) {
    var value = event.request.querystring[key];
    if (value.multiValue) {
      for (var v in value.multiValue) {
        query.push(key + "=" + encodeURIComponent(value.multiValue[v].value));
      }
    } else {
      query.push(key + "=" + encodeURIComponent(value.value));
    }
  }
  return [path, query.join("&")].join("?");
}

function addAccessControlHeaders(event, response) {
  if (!event.request.headers.origin) return response;

  response.headers["access-control-allow-origin"] = { value: event.request.headers.origin.value };
  response.headers["access-control-allow-methods"] = { value: "HEAD, GET, OPTIONS" };
  response.headers["access-control-allow-credentials"] = { value: "true" };
  return response;
}

function handler(event) {
  var originalHost    = event.request.headers.host.value;
  var targetHost      = mappings[originalHost];
  
  if (!(originalHost && targetHost)) {
    return {
      statusCode: 400,
      statusDescription: "Bad Request"
    }
  }

  var response = {
    statusCode: responseStatus,
    statusDescription: statusCodeDescriptions[responseStatus],
    headers: {
      location: { 
        value: "https://" + targetHost + "/" + pathPlusQuery(event) 
      }
    }
  };

  return addAccessControlHeaders(event, response);
};
