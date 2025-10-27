#!/usr/bin/env python3
"""
Script to detect Lambda layers and layer versions not attached to any Lambda functions.
Requires: boto3, AWS credentials configured
"""

import boto3
from collections import defaultdict
import json
import argparse
import sys

def get_all_lambdas(client, region):
    """Get all Lambda functions in the region."""
    functions = []
    paginator = client.get_paginator('list_functions')
    
    for page in paginator.paginate():
        functions.extend(page['Functions'])
    
    return functions

def get_all_layers(client):
    """Get all Lambda layers."""
    layers = []
    paginator = client.get_paginator('list_layers')
    
    for page in paginator.paginate():
        layers.extend(page['Layers'])
    
    return layers

def get_layer_versions(client, layer_name):
    """Get all versions for a specific layer."""
    versions = []
    paginator = client.get_paginator('list_layer_versions')
    
    for page in paginator.paginate(LayerName=layer_name):
        versions.extend(page['LayerVersions'])
    
    return versions

def extract_layer_arns_from_functions(functions):
    """Extract all layer ARNs used by Lambda functions."""
    used_layer_arns = set()
    
    for func in functions:
        if 'Layers' in func:
            for layer in func['Layers']:
                used_layer_arns.add(layer['Arn'])
    
    return used_layer_arns

def delete_layer_version(client, layer_name, version_number, dry_run=False):
    """Delete a specific layer version."""
    if dry_run:
        print(f"    [DRY RUN] Would delete {layer_name} version {version_number}")
        return True
    
    try:
        client.delete_layer_version(
            LayerName=layer_name,
            VersionNumber=version_number
        )
        print(f"    ✓ Deleted {layer_name} version {version_number}")
        return True
    except Exception as e:
        print(f"    ✗ Failed to delete {layer_name} version {version_number}: {str(e)}")
        return False

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description='Detect and optionally delete unused Lambda layers and layer versions'
    )
    parser.add_argument(
        '--delete',
        action='store_true',
        help='Delete unused layer versions (requires confirmation)'
    )
    parser.add_argument(
        '--delete-all-versions',
        action='store_true',
        help='Delete ALL unused layer versions for completely unused layers'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be deleted without actually deleting'
    )
    parser.add_argument(
        '--no-confirm',
        action='store_true',
        help='Skip confirmation prompts (use with caution!)'
    )
    parser.add_argument(
        '--region',
        type=str,
        help='AWS region (default: uses configured region)'
    )
    
    args = parser.parse_args()
    
    # Initialize boto3 client
    session = boto3.Session()
    region = args.region or session.region_name or 'us-east-1'
    
    print(f"Scanning Lambda layers in region: {region}\n")
    
    client = boto3.client('lambda', region_name=region)
    
    # Get all functions and extract used layer ARNs
    print("Fetching all Lambda functions...")
    functions = get_all_lambdas(client, region)
    used_layer_arns = extract_layer_arns_from_functions(functions)
    print(f"Found {len(functions)} Lambda functions using {len(used_layer_arns)} layer versions\n")
    
    # Get all layers
    print("Fetching all Lambda layers...")
    layers = get_all_layers(client)
    print(f"Found {len(layers)} layers\n")
    
    # Track unused layers and versions
    unused_layers = []
    unused_versions = []
    
    # Check each layer and its versions
    for layer in layers:
        layer_name = layer['LayerName']
        layer_arn = layer['LayerArn']
        
        print(f"Checking layer: {layer_name}")
        versions = get_layer_versions(client, layer_name)
        
        layer_has_used_version = False
        
        for version in versions:
            version_arn = version['LayerVersionArn']
            version_number = version['Version']
            
            if version_arn not in used_layer_arns:
                unused_versions.append({
                    'LayerName': layer_name,
                    'Version': version_number,
                    'Arn': version_arn,
                    'CreatedDate': version.get('CreatedDate', 'N/A')
                })
            else:
                layer_has_used_version = True
        
        # If no versions of this layer are used, mark the layer as unused
        if not layer_has_used_version:
            unused_layers.append({
                'LayerName': layer_name,
                'LayerArn': layer_arn,
                'LatestVersion': layer['LatestMatchingVersion']['Version']
            })
    
    # Print results
    print("\n" + "="*80)
    print("RESULTS")
    print("="*80)
    
    if unused_layers:
        print(f"\n🔴 Completely unused layers (no versions attached to any function): {len(unused_layers)}")
        print("-" * 80)
        for layer in unused_layers:
            print(f"  • {layer['LayerName']} (v{layer['LatestVersion']})")
            print(f"    ARN: {layer['LayerArn']}")
    else:
        print("\n✅ No completely unused layers found")
    
    if unused_versions:
        print(f"\n🟡 Unused layer versions: {len(unused_versions)}")
        print("-" * 80)
        
        # Group by layer name
        versions_by_layer = defaultdict(list)
        for version in unused_versions:
            versions_by_layer[version['LayerName']].append(version)
        
        for layer_name, versions in sorted(versions_by_layer.items()):
            print(f"  • {layer_name}:")
            for v in sorted(versions, key=lambda x: x['Version']):
                print(f"    - Version {v['Version']} (Created: {v['CreatedDate']})")
                print(f"      ARN: {v['Arn']}")
    else:
        print("\n✅ No unused layer versions found")
    
    # Summary
    print("\n" + "="*80)
    print("SUMMARY")
    print("="*80)
    print(f"Total Lambda functions: {len(functions)}")
    print(f"Total layers: {len(layers)}")
    print(f"Completely unused layers: {len(unused_layers)}")
    print(f"Unused layer versions: {len(unused_versions)}")
    print(f"Used layer versions: {len(used_layer_arns)}")
    
    # Export to JSON if needed
    output = {
        'region': region,
        'unused_layers': unused_layers,
        'unused_versions': unused_versions,
        'summary': {
            'total_functions': len(functions),
            'total_layers': len(layers),
            'unused_layers_count': len(unused_layers),
            'unused_versions_count': len(unused_versions),
            'used_versions_count': len(used_layer_arns)
        }
    }
    
    with open('unused_lambda_layers.json', 'w') as f:
        json.dump(output, f, indent=2, default=str)
    
    print(f"\n📄 Results exported to: unused_lambda_layers.json")
    
    # Handle deletion if requested
    if args.delete or args.delete_all_versions:
        print("\n" + "="*80)
        print("DELETION OPTIONS")
        print("="*80)
        
        if args.dry_run:
            print("\n🔍 DRY RUN MODE - No actual deletions will be performed\n")
        
        deletion_targets = []
        
        if args.delete_all_versions and unused_layers:
            # Delete all versions of completely unused layers
            for layer in unused_layers:
                layer_name = layer['LayerName']
                versions = get_layer_versions(client, layer_name)
                for version in versions:
                    deletion_targets.append({
                        'layer_name': layer_name,
                        'version': version['Version']
                    })
        elif args.delete:
            # Delete only unused versions
            for version in unused_versions:
                deletion_targets.append({
                    'layer_name': version['LayerName'],
                    'version': version['Version']
                })
        
        if not deletion_targets:
            print("\n✅ No unused layer versions to delete")
        else:
            print(f"\n📋 Found {len(deletion_targets)} layer version(s) to delete:")
            for target in deletion_targets[:10]:  # Show first 10
                print(f"  • {target['layer_name']} v{target['version']}")
            if len(deletion_targets) > 10:
                print(f"  ... and {len(deletion_targets) - 10} more")
            
            # Confirmation prompt
            if not args.no_confirm and not args.dry_run:
                print("\n⚠️  WARNING: This action cannot be undone!")
                response = input(f"\nAre you sure you want to delete {len(deletion_targets)} layer version(s)? (yes/no): ")
                if response.lower() != 'yes':
                    print("❌ Deletion cancelled")
                    return
            
            # Perform deletions
            print("\n🗑️  Deleting layer versions...")
            success_count = 0
            fail_count = 0
            
            for target in deletion_targets:
                if delete_layer_version(
                    client,
                    target['layer_name'],
                    target['version'],
                    dry_run=args.dry_run
                ):
                    success_count += 1
                else:
                    fail_count += 1
            
            print(f"\n✅ Successfully deleted: {success_count}")
            if fail_count > 0:
                print(f"❌ Failed to delete: {fail_count}")
            
            if args.dry_run:
                print("\n💡 Run without --dry-run to actually delete these versions")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n❌ Error: {str(e)}")
        raise