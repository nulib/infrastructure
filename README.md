![terraform style](https://github.com/nulib/infrastructure/actions/workflows/tflint.yml/badge.svg)

## Description

NUL projects such as [Meadow](https://github.com/nulib/meadow) and [AVR](https://github.com/nulib/avalon) have their own `terraform` directories where their app-specific resources are managed. This repository is for resources (such as the VPC/Firewall, or third-party pieces like Fedora, Solr, etc.) that don't have another specific project managing them.

Each top-level folder represents a discrete piece of infrastructure, and we should strive to keep them relatively small and self-contained. Their resources and outputs can be referenced from other terraform projects in one of several ways:

* The [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
* Terraform [Remote State](https://www.terraform.io/docs/language/state/remote.html)
* Variable files

## Coding Conventions

Each folder should follow the same naming conventions:

* `main.tf` – The main terraform manifest for the folder, where the provider, backend, and primary resources are specified
* `variables.tf` – Contains variable declarations, and any locals derived *only* from variables
* `data.tf` – Contains terraform `data` sources, if there are enough of them to warrant splitting them out
* `outputs.tf` – Contains only terraform outputs

## Variables

Variables are stored in files following the naming convention `[environment].tfvars`. They should not be checked into github in this project. Instead, create them in a reasonably named subdirectory within the [tfvars](https://github.com/nulib/tfvars) project and symlink them to where you need them in this project.

## Common Configuration

Each folder should be initialized the same way:

* Use the AWS provider with an S3 backend:

    ```
    terraform {
      backend "s3" {
        key    = "[project_or_folder_name].tfstate" # e.g., `solrcloud.tfstate` or `staging-waf.tfstate`
      }
    }

    provider "aws" {
      region = var.aws_region
    }
    ```

When running `terraform init`:

* Use `nulterra-state-sandbox` as the remote S3 bucket

Before running `terraform plan` or `terraform apply`:
* Create or select a workspace with the same name as the environment you're deploying to, e.g.:
    ```
    $ terraform workspace select staging
    ```
    or (if the workspace doesn't exist yet)
    ```
    $ terraform workspace new production
    ```

## Shared Modules

Reusable groups of resources can be assembled into [modules](https://www.terraform.io/docs/language/modules/develop/index.html) with their own variables and outputs. Modules can be very useful, but can also greatly increase the complexity of the project. Any reusable modules we create can be put in the `modules` folder. If used by other projects within this repo, they can be referenced by the relative path from the project folder (e.g., `../modules/some_module`). If used by terraform code owned by another project, they can be referenced using an HTTP url scheme (e.g., `git::https://github.com/nulib/infrastructure.git//modules/my_module`).

If modules develop to a point where they need to be released and versioned, we can look into using a module registry.