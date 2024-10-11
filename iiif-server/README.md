# iiif-server

This SAM project project includes the viewer-request function and SAM template required to install and configure the NUL IIIF Server.

## Usage

The `config-env` parameter will always be the environment you're deploying to (e.g., `staging`)

### First Use
```
sam build
sam deploy --config-env staging --guided
```

This will prompt for all of the deploy parameters, and then give you the option to save them in a config file for later use.

### Subsequent Use
```
sam build
sam deploy --config-env staging
```

This will use the previously saved config file

## Deploy parameters

  - `Hostname`: The host part of the server FQDN (e.g., `iiif`)
  - `DomainName`: The domain part of the server FQDN (e.g., `rdc.library.northwestern.edu`)
  - `AllowFromReferers`: A regular expression to match against the Referer header for pass-through - `authorization` (Default: `""`)
  - `CertificateArn`: The ARN of an SSL certificate that matches the server FQDN
  - `DcApiEndpoint`: The public endpoint for the DC API
  - `IiifLambdaMemory`: The amount of memory in MB for the IIIF lambda to use (Default: `2048`)
  - `IiifLambdaTimeout`: The timeout for the IIIF lambda (Default: `10`)
  - `Namespace`: The infrastructure namespace prefix to use for secrets management
  - `ServerlessIiifVersion`: The version of Serverless IIIF to deploy (Default: `5.0.0`)
  - `SourceBucket`: The bucket where the pyramid TIFF images are stored

## IIIF requests with signed urls

Optionally, the viewer function supports HMAC-signed URLs with an expires parameter.

- URL will take the form `https://iiif-server.domain/iiif/:version/:id/:region/:size/:rotation/:quality.:format?Auth-Signature=:jwt`
- JWT will be signed using symmetric HMAC encryption and the same key we currently use for the cookie auth JWTs
- JWT will have the following structure:
    ```javascript
    {
      "sub": "my-image-id",           // image ID, required
      "region": ["0,0,256,256"],      // list of valid IIIF region values, optional
      "size": ["pct:50"],             // list of valid IIIF size values, optional
      "rotation": ["0", "180", "!0"], // list of valid IIIF rotation values, optional
      "quality": ["bitonal", "gray"], // list of valid IIIF quality values, optional
      "format": ["jpg", "png"],       // list of valid IIIF format values, optional
      "max-width": 1024,              // maximum width in pixels, optional
      "max-height": 768               // maximum height in pixels, optional
      "exp": 1687550764               // expiration timestamp, required
    }
    ```
The request will be validated based on the fields present in the JWT.
- The `sub` field _must_ match the `:id` of the request.
- Any other IIIF spec field (`region`, `size`, `rotation`, `quality`, `format`), if present, will limit the valid values in the request. If the requested value does not appear in the list, the request will be denied. If a field is not present, any valid value is acceptable.
- If `max-width` and/or `max-height` is present, it will limit the size of the *full-frame image* that can be retrieved. That is, the authorizer will determine what the size of the whole image would be _after_ the region and size parameters are taken into account, and only authorize the request if both dimensions are less than or equal to `max-width` and `max-height`.
- The `exp` field indicates the time (expressed as seconds since the UNIX epoch) beyond which the signature is no longer valid.
