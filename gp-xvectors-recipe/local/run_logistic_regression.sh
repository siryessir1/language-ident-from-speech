#!/bin/bash
# Copyright  2014   David Snyder,  Daniel Povey
# Apache 2.0.
#
# This script trains a logistic regression model on top of
# X-vectors, and evaluates it on given set of test X-vectors.

. ./cmd.sh
. ./path.sh
set -e

## All these now provided as arguments when calling this script
prior_scale=1.0
conf="NONE" # conf/logistic-regression.conf
train_dir="NONE" # exp/ivectors_train
test_dir="NONE" # exp/ivectors_lre07
model_dir="NONE" # exp/ivectors_train
train_utt2lang="NONE" # data/train_lr/utt2lang
test_utt2lang="NONE" # data/lre07/utt2lang
languages="NONE" # conf/test_languages.list

apply_log=true # If true, the output of the binary
               # logistitic-regression-eval are log-posteriors.
               # Probabilities are the output if this is false.

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

mkdir -p $model_dir/log

model=$model_dir/logistic_regression
model_rebalanced=$model_dir/logistic_regression_rebalanced
train_xvectors="ark:ivector-normalize-length scp:$train_dir/xvector.scp ark:- |";
test_xvectors="ark:ivector-normalize-length scp:$test_dir/xvector.scp ark:- |";
classes="ark:cat $train_utt2lang | utils/sym2int.pl -f 2 $languages - |"

# A uniform prior.
#utils/sym2int.pl -f 2 $languages \
#  <(cat $train_utt2lang) | \
#  awk '{print $2}' | sort -n | uniq -c | \
#  awk 'BEGIN{printf(" [ ");} {printf("%s ", 1.0/$1); } END{print(" ]"); }' \
#   >$model_dir/inv_priors.vec

# Create priors to rebalance the model. The following script rebalances
# the languages as ( count(lang_test) / count(lang_train) )^(prior_scale).
./local/balance_priors_to_test.pl \
    <(utils/filter_scp.pl -f 1 \
      $train_dir/xvector.scp $train_utt2lang) \
    <(cat $test_utt2lang) \
    $languages \
    $prior_scale \
    $model_dir/priors.vec

logistic-regression-train \
  --config=$conf \
  "$train_xvectors" \
  "$classes" \
  $model \
  2>$model_dir/log/logistic_regression.log

logistic-regression-copy \
  --scale-priors=$model_dir/priors.vec \
  $model \
  $model_rebalanced

## Evaluate on train data.
# logistic-regression-eval --apply-log=$apply_log $model \
#   "$train_xvectors" ark,t:$train_dir/posteriors
# cat $train_dir/posteriors | \
#   awk '{max=$3; argmax=3; for(f=3;f<NF;f++) { if ($f>max) 
#                           { max=$f; argmax=f; }}  
#                           print $1, (argmax - 3); }' | \
#   utils/int2sym.pl -f 2 $languages \
#     >$train_dir/output
# compute-wer \
#   --mode=present \
#   --text ark:<(cat $train_utt2lang) \
#   ark:$train_dir/output

# Evaluate on test data.
logistic-regression-eval \
  --apply-log=$apply_log \
  $model_rebalanced \
  "$test_xvectors" ark,t:$test_dir/posteriors

cat $test_dir/posteriors | \
  awk '{max=$3; argmax=3; for(f=3;f<NF;f++) { if ($f>max) 
                          { max=$f; argmax=f; }}  
                          print $1, (argmax - 3); }' | \
  utils/int2sym.pl -f 2 $languages \
    >$test_dir/output

# Note: we treat the language as a sentence.
compute-wer \
  --mode=present \
  --text ark:<(cat $test_utt2lang) \
  ark:$test_dir/output