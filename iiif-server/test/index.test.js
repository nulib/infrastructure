import { beforeAll, beforeEach, describe, expect, mock, test } from "bun:test";

const ID = "e8d28223-7237-43ac-a905-c7825e1d188f";
const DC_API = "https://dcapi.example.edu/api/v2";
const config = {
  allowFrom: "dc\\.example\\.edu",
  dcApiEndpoint: DC_API,
  tiffBucket: "test-pyramids",
  apiTokenKey: "test-key"
};

// Stand in for Secrets Manager: hand the handler a fixed config
mock.module("@middy/secrets-manager", () => ({
  default: () => ({
    before: (request) => {
      request.context.config = config;
    }
  })
}));

// Stand in for the DC API: only the real file set ID is authorized
const fetchCalls = [];
mock.module("node-fetch", () => ({
  default: async (url) => {
    fetchCalls.push(url);
    const status = url === `${DC_API}/file-sets/${ID}/authorization` ? 204 : 404;
    return { status };
  }
}));

// Only used for max-width/max-height JWT claims, which these tests don't exercise
mock.module("iiif-processor/calculator", () => ({ default: {} }));

let handler;
beforeAll(async () => {
  ({ handler } = await import("../src/index.js"));
});

beforeEach(() => {
  fetchCalls.length = 0;
});

function viewerRequest(uri) {
  return {
    Records: [
      {
        cf: {
          config: { eventType: "viewer-request" },
          request: {
            method: "GET",
            uri,
            querystring: "",
            clientIp: "127.0.0.1",
            headers: {}
          }
        }
      }
    ]
  };
}

async function authorized(uri) {
  const result = await handler(viewerRequest(uri), {});
  return result.status !== "403";
}

describe("viewer-request authorization", () => {
  test("base URI with a trailing slash is authorized", async () => {
    expect(await authorized(`/iiif/3/${ID}/`)).toBe(true);
  });

  test("base URI without a trailing slash is authorized", async () => {
    expect(await authorized(`/iiif/3/${ID}`)).toBe(true);
    expect(fetchCalls).not.toContain(`${DC_API}/file-sets/3/authorization`);
  });

  test("info.json is authorized without calling the DC API", async () => {
    expect(await authorized(`/iiif/3/${ID}/info.json`)).toBe(true);
    expect(fetchCalls).toEqual([]);
  });

  test("image request checks the DC API for the requested ID", async () => {
    expect(await authorized(`/iiif/3/${ID}/full/max/0/default.jpg`)).toBe(true);
    expect(fetchCalls).toEqual([`${DC_API}/file-sets/${ID}/authorization`]);
  });

  test("image request for an unauthorized ID is forbidden", async () => {
    const other = "00000000-0000-0000-0000-000000000000";
    expect(await authorized(`/iiif/3/${other}/full/max/0/default.jpg`)).toBe(false);
  });

  test("authorized request is routed to the pyramid TIFF", async () => {
    const result = await handler(viewerRequest(`/iiif/3/${ID}`), {});
    expect(result.headers["x-preflight-location"][0].value).toBe(
      `s3://test-pyramids/e8/d2/82/23/-7/23/7-/43/ac/-a/90/5-/c7/82/5e/1d/18/8f-pyramid.tif`
    );
  });
});
