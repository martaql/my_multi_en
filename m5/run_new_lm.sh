#!/bin/bash

stage=3
substage=2
#home_dir=pwd

. ./cmd.sh

. ./path.sh

if [ $stage -eq 0 ]; then
  mkdir -p data
  mkdir -p data/local
  mkdir -p data/local/lm
  mkdir -p data/local/tmp
fi

lang_mod=wsj
lm_suffix=wsj
dict_root=data/local/dict
lang_root=data/lang
lm_root=data/local/lm
tmp_dir=data/local/tmp

dict_dir=${dict_root}_${lm_suffix}
lang_dir=${lang_root}_${lm_suffix}
lm_dir=${lm_root}/lm_${lm_suffix}
librispeech_data_dir=../../librispeech/s5/data
wsj0=~/data/wsj/LDC/LDC93S6B
wsj1=~/data/wsj/LDC/LDC94S13B


if [ $stage -eq 1 ]; then
	
  if [ $substage -le 0 ]; then
    rm -rf $lm_dir
    mkdir -p $lm_dir
    # The 20K vocab, open-vocabulary language model (i.e. the one with UNK), without
    # verbalized pronunciations. This is the most common test setup, I understand.
    # Trigram would be:
    #cat links/13-32.1/wsj1/doc/lng_modl/base_lm/tcb20onp.z | \
    #  perl -e 'while(<>){ if(m/^\\data\\/){ print; last;  } } while(<>){ print; }' | \
    #  gzip -c -f > $lm_dir/lm_tg.arpa.gz
    # Pruned trigram would be:
    #prune-lm --threshold=1e-7 $lm_dir/lm_tg.arpa.gz $lm_dir/lm_tgpr.arpa
    #gzip -f $lm_dir/lm_tgpr.arpa

    cp ../../wsj/s5/data/local/nist_lm/{lm_tgpr,lm_tg}.arpa.gz $lm_dir
    echo "End of substage 0"
  fi
  
  if [ $substage -eq 1 ]; then
    # Prepare dict_wsj and dict_wsj_larger
    local/my_wsj_prepare_dict.sh --dict_suffix _$lm_suffix
    echo "End of substage 1"
  fi

  if [ $substage -eq 2 ]; then
    # Prepare lang and lm for short dictionary
    rm -rf ${lang_dir}
    rm -rf $tmp_dir/lang_tmp_$lm_suffix
    # Prepare lang_wsj
    utils/prepare_lang.sh \
       --phone-symbol-table $librispeech_data_dir/lang_nosp/phones.txt \
      ${dict_dir} "<UNK>" \
      $tmp_dir/lang_tmp_${lm_suffix} ${lang_dir}  || exit 1;
    # Preparing short language models for test
    #cp ../../wsj/s5/data/local/nist_lm/{lm_tgpr,lm_tg}.arpa.gz $lm_dir
    for lm_sub_suffix in tgpr tg; do
      test=${lang_dir}_test_${lm_sub_suffix}
      rm -rf $test
      mkdir -p $test
      cp -r ${lang_dir}/* $test || exit 1;
      gunzip -c $lm_dir/lm_${lm_sub_suffix}.arpa.gz | \
        arpa2fst --disambig-symbol=#0 \
        --read-symbol-table=$test/words.txt - $test/G.fst
      utils/validate_lang.pl --skip-determinization-check $test || exit 1;
    done

  fi

  if [ $substage -eq 3 ]; then
    rm -rf ${lang_dir}
    rm -rf $tmp_dir/lang_tmp_${lm_suffix}_bd
    # Prepare lang_wsj_bd
    utils/prepare_lang.sh \
      --phone-symbol-table $librispeech_data_dir/lang_nosp/phones.txt \
      ${dict_dir}_larger "<UNK>" \
      $tmp_dir/lang_tmp_${lm_suffix}_bd ${lang_dir}_bd	
    rm -rf ${lang_dir}_test_bd*    
    # Train language models (only 3gram)
    local/wsj_train_lms.sh --dict-suffix "_${lm_suffix}" $lm_dir  || exit 1;
    # Format language Models (only tgpr and tg)
    local/wsj_format_local_lms.sh --lang-suffix "_${lm_suffix}" $lm_dir  || exit 1;
    echo "End of substage 1"
  fi
  echo "End of stage 1"
fi

#exit 0

if [ $stage -eq 2 ]; then     
    
  if [ $substage -eq 0 ]; then
    rm -rf $tmp_dir/*$lm_suffix*
    rm -rf $lm_dir
    mkdir -p $lm_dir
    #Copy or download the LM resources
    #lm_url=www.openslr.org/resources/11
    #local/librispeech_download_lm.sh $lm_url $lm_dir  
    lm_link=../../librispeech/s5/data/local/lm
    cp $lm_link/* $lm_dir/
    echo "End of substage 0"
  fi

  if [ $substage -eq 1 ]; then
    #Copy phone-files from librispeech data-dir
    librispeech_data_dir=../../librispeech/s5/data
    rm -rf mkdir ${dict_dir}
    mkdir ${dict_dir}
    cp $librispeech_data_dir/local/dict_nosp/{extra_questions,nonsilence_phones,optional_silence,silence_phones,lexicon}.txt \
      ${dict_dir}
    echo "End of substage 1"
  fi

  if [ $substage -le 2 ]; then	  
    # Prepare Lang using Librispeech dict
    utils/prepare_lang.sh \
      --phone-symbol-table ../s5/data/lang_nosp/phones.txt \
      ${dict_dir} "<UNK>" \
      $tmp_dir/lang_tmp_${lm_suffix} ${lang_dir}
    #Format language models
    local/librispeech_format_lms.sh --src-dir ${lang_dir} $lm_dir
    #Create ConstArpaLm format language model for full 3-gram and 4-gram LMs
    utils/build_const_arpa_lm.sh \
      $lm_dir/lm_tglarge.arpa.gz \
      ${lang_dir} ${lang_dir}_test_tglarge
    utils/build_const_arpa_lm.sh \
      $lm_dir/lm_fglarge.arpa.gz \
      ${lang_dir} ${lang_dir}_test_fglarge
    
    echo "End of substage 2"
  fi
    
  echo "End of stage 2"
fi

#exit 0

if [ $stage -eq 3 ]; then  
  #################################################
  #langdir=data/lang_wsj_test_bd_tgpr
  #langdir=data/lang_librispeech_test_tgsmall
  #################################################
  #modeldir=../s5/exp/tri3b_sat
  #################################################
  #outputdir=models/tri3b_sat_wsj_test_bd_tgpr
  #outputdir=models/tri3b_sat_librispeech_test_tgsmall
  #################################################
  #mkdir -p exp

  for lmtype in libri; do # wsj libri; do

    if [ $lang_mod = 'libri' ]; then
      modeltype=libri_tri4b
      model_dir=../../librispeech/s5/exp/tri4b
      #modeltype=wsj_tri3b_sat
      #model_dir=../s5/exp/multi_m/tri3b_sat
      output_dir=exp/${modeltype}_$lm_suffix   
    fi
    if [ $lang_mod = 'wsj_ls' ]; then
      modeltype=libri_tri4b
      model_dir=../../librispeech/s5/exp/tri4b
      output_dir=exp/${modeltype}_$lm_suffix
    fi
    #rm -rf $output_dir
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
  done
  
  echo "End of stage 3"
fi

#exit 0

if [ $stage -le 4 ]; then

  for test_data in wsj; do # wsj libri; do

    if [ $lang_mod = 'libri' ]; then
      #model=libri_tri4b
      model=wsj_tri3b_sat
      model_dir=exp/${model}_${lm_suffix}
      utils/mkgraph.sh data/lang_${lm_suffix}_test_tgsmall $model_dir \
        $model_dir/graph_${lm_suffix}_tgsmall
      steps/decode_fmllr.sh --nj 20 --cmd "$decode_cmd" \
        $model_dir/graph_${lmtype}_tgsmall data/$test_data/test  \
        $model_dir/decode_${lmtype}_tgsmall
      steps/lmrescore.sh --cmd "$decode_cmd" data/lang_${lm_suffix}_test_{tgsmall,tgmed} \
        data/$test_data/test  $model_dir/decode_${lm_suffix}_{tgsmall,tgmed}
      steps/lmrescore_const_arpa.sh
        --cmd "$decode_cmd" data/lang_${lm_suffix}_test_{tgsmall,tglarge} \
        data/$test_data/test  $model_dir/decode_${lm_suffix}_{tgsmall,tglarge}
      steps/lmrescore_const_arpa.sh \
        --cmd "$decode_cmd" data/lang_${lm_suffix}_test_{tgsmall,fglarge} \
        data/$test_data/test  $model_dir/decode_${lm_suffix}_{tgsmall,fglarge}
    fi

        
    if [ $lang_mod = 'wsj' ]; then
      model=libri_tri4b
      model_dir=exp/${model}_$lm_suffix
      utils/mkgraph.sh data/lang_${lm_suffix}_test_bd_tgpr $model_dir \
        $model_dir/graph_${lm_suffix}_bd_tgpr
      steps/decode_fmllr.sh --cmd "$decode_cmd" --nj 8  \
        $model_dir/graph_${lm_suffix}_bd_tgpr \
        data/$test_data/test $model_dir/decode_${lm_suffix}_bd_tgpr
       steps/lmrescore.sh --cmd "$decode_cmd" \
        data/lang_${lm_suffix}_test_bd_tgpr data/lang_${lm_suffix}_test_bd_tg \
        data/$test_data/test $model_dir/decode_${lm_suffix}_bd_{tgpr,tg}
    fi

    isayso=false
    if $isayso; then
      model=libri_tri4b
      model_dir=exp/${model}_$lm_suffix
      utils/mkgraph.sh data/lang_${lm_suffix}_test_tgpr $model_dir \
        $model_dir/graph_${lm_suffix}_tgpr
      steps/decode_fmllr.sh --cmd "$decode_cmd" --nj 8  \
        $model_dir/graph_${lm_suffix}_tgpr \
        data/$test_data/test $model_dir/decode_${lm_suffix}_tgpr
       steps/lmrescore.sh --cmd "$decode_cmd" \
        data/lang_${lm_suffix}_test_tgpr data/lang_${lm_suffix}_test_tg \
        data/$test_data/test $model_dir/decode_${lm_suffix}_{tgpr,tg}
    fi

  done

  echo "End of stage 4"
fi

#exit 0

if [ $stage -le 6 ]; then
  # getting results (see RESULTS file)
  for lmtype in libri wsj; do
    echo "=== test set $lmtype ===" ;
    for x in exp/*tri*/decode_${lmtype}_*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done ;
  done > RESULTS_marta
  echo "End of stage 6"
fi

#exit 0
