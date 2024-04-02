#!/bin/bash

# Ensure working directory is project root
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $__dir
# Load all environment variables
export $(cat .env.backup | xargs)
