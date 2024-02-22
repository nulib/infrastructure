#!/bin/bash

mkdir -p .working
cd .working
git lfs install
git clone https://huggingface.co/$repository
mkdir -p $model_id/code/
cp ../inference.py $model_id/code/
tar zcvf ${model_id}.tar.gz -C $model_id --exclude '.git*' .
