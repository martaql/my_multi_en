#!/bin/bash

librispeech_data_dir=../../librispeech/s5/data
mkdir -p data1

cp -r $librispeech_data_dir/lang_nosp_test* data1/

modeltype=libri_tri4b
model_dir=../../librispeech/s5/exp/tri4b
output_dir=exp/libri_tri4b_libri
mkdir -p $output_dir

mkdir -p $output_dir
model=$model_dir/final.mdl
tree=$model_dir/tree
cp $model $tree $output_dir
for optsfile in splice_opts cmvn_opts delta_opts; do
  if [ -e $model_dir/$optsfile ]; then
    cp $model_dir/$optsfile $output_dir
  fi
done
for file_end in mat alimdl nnet feature_transform ; do
  if [ -e $model_dir/final.$file_end ]; then
    cp $model_dir/final.$file_end $output_dir
  fi
done
for file in prior_counts ali_train_pdf.counts ; do
  if [ -e $model_dir/$file ]; then
    cp $model_dir/$file $output_dir
  fi
done

test_data=wsj
lm_suffix=nosp
model=libri_tri4b_libri
model_dir=exp/${model}
utils/mkgraph.sh data1/lang_${lm_suffix}_test_tgsmall $model_dir \
  $model_dir/graph_${lm_suffix}_tgsmall
steps/decode_fmllr.sh --nj 8 --cmd "$decode_cmd" \
  $model_dir/graph_${lm_suffix}_tgsmall data/$test_data/test  \
  $model_dir/decode_${lm_suffix}_tgsmall
steps/lmrescore.sh --cmd "$decode_cmd" data/lang_${lm_suffix}_test_{tgsmall,tgmed} \
  data/$test_data/test  $model_dir/decode_${lm_suffix}_{tgsmall,tgmed}
steps/lmrescore_const_arpa.sh
  --cmd "$decode_cmd" data/lang_${lm_suffix}_test_{tgsmall,tglarge} \
  data/$test_data/test  $model_dir/decode_${lm_suffix}_{tgsmall,tglarge}
steps/lmrescore_const_arpa.sh \
  --cmd "$decode_cmd" data/lang_${lm_suffix}_test_{tgsmall,fglarge} \
  data/$test_data/test  $model_dir/decode_${lm_suffix}_{tgsmall,fglarge}



for lmtype in libri wsj; do
  echo "=== test set $lmtype ===" ;
  for x in exp/*tri*/decode_${lmtype}_*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done ;
done > RESULTS_marta
