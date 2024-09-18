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
