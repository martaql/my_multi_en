#!/bin/bash

# The parts of the output of this that will be needed are
# [in data/local/dict/ ]
# lexicon.txt
# extra_questions.txt
# nonsilence_phones.txt
# optional_silence.txt
# silence_phones.txt

dict_suffix=

echo "$0 $@"  # Print the command line for logging
. utils/parse_options.sh || exit 1;

dir=data/local/dict${dict_suffix}
rm -rf $dir
mkdir -p $dir

# (1) Get the CMU dictionary
svn co https://svn.code.sf.net/p/cmusphinx/code/trunk/cmudict \
  $dir/cmudict || exit 1;

# can add -r 10966 for compatibility with wsj
# can add -r 12440 for strict compatibility librispeech

libri_mode=true
silence_phones=$dir/silence_phones.txt
optional_silence=$dir/optional_silence.txt
nonsil_phones=$dir/nonsilence_phones.txt
extra_questions=$dir/extra_questions.txt

if $libri_mode; then 
  cp data/local/lm/lm_libri/librispeech-lexicon.txt $dir/lexicon_raw_nosil.txt
  awk '{for (i=2; i<=NF; ++i) { print $i; gsub(/[0-9]/, "", $i); print $i}}' $dir/lexicon_raw_nosil.txt |\
    sort -u |\
    perl -e 'while(<>){
      chop; m:^([^\d]+)(\d*)$: || die "Bad phone $_";
      $phones_of{$1} .= "$_ "; }
      foreach $list (values %phones_of) {print $list . "\n"; } ' | sort \
      > $nonsil_phones || exit 1;
else
  # nonsilence phones; on each line is a list of phones that correspond
  # really to the same base phone.
  cat $dir/cmudict/cmudict.0.7a.symbols | perl -ane 's:\r::; print;' | \
    sort -u |\
    perl -e 'while(<>){
      chop; m:^([^\d]+)(\d*)$: || die "Bad phone $_"; 
      $phones_of{$1} .= "$_ "; }
      foreach $list (values %phones_of) {print $list . "\n"; } ' | sort \
      > $nonsil_phones || exit 1;
  grep -v ';;;' $dir/cmudict/cmudict.0.7a | \
    perl -ane 'if(!m:^;;;:){ s:(\S+)\(\d+\) :$1 :; print; }' \
      > $dir/lexicon_raw_nosil.txt || exit 1;
fi

echo "Preparing phone lists and clustering questions"
  (echo SIL; echo SPN;) > $silence_phones
  echo SIL > $optional_silence
# nonsilence phones; on each line is a list of phones that correspond
# really to the same base phone.
cat $dir/cmudict/cmudict.0.7a.symbols | perl -ane 's:\r::; print;' | \
 perl -e 'while(<>){
  chop; m:^([^\d]+)(\d*)$: || die "Bad phone $_"; 
  $phones_of{$1} .= "$_ "; }
  foreach $list (values %phones_of) {print $list . "\n"; } ' \
  > $nonsil_phones || exit 1;
# A few extra questions that will be added to those obtained by automatically clustering
# the "real" phones.  These ask about stress; there's also one for silence.
cat $silence_phones| awk '{printf("%s ", $1);} END{printf "\n";}' > $extra_questions || exit 1;
cat $nonsil_phones | perl -e 'while(<>){ foreach $p (split(" ", $_)) {
$p =~ m:^([^\d]+)(\d*)$: || die "Bad phone $_"; $q{$2} .= "$p "; } } foreach $l (values %q) {print "$l\n";}' \
>> $extra_questions || exit 1;
echo "$(wc -l <$silence_phones) silence phones saved to: $silence_phones"
echo "$(wc -l <$optional_silence) optional silence saved to: $optional_silence"
echo "$(wc -l <$nonsil_phones) non-silence phones saved to: $nonsil_phones"
echo "$(wc -l <$extra_questions) extra triphone clustering-related questions saved to: $extra_questions"

grep -v ';;;' $dir/cmudict/cmudict.0.7a | \
 perl -ane 'if(!m:^;;;:){ s:(\S+)\(\d+\) :$1 :; print; }' \
  > $dir/lexicon_raw_nosil.txt || exit 1;

(echo '!SIL SIL'; echo '<SPOKEN_NOISE> SPN'; echo '<UNK> SPN'; echo '<NOISE> SPN';  ) |\
  cat - $dir/lexicon_raw_nosil.txt | sort | uniq >$dir/lexicon.txt

echo "Lexicon text file saved as: $dir/lexicon.txt"

wsj1=~/data/wsj/LDC/LDC94S13B
srcdir=$wsj1/13-32.1
dir=data/local/dict${dict_suffix}_larger
rm -rf $dir
mkdir -p $dir
cp -r data/local/dict${dict_suffix}/* \
  data/local/dict${dict_suffix}_larger # Various files describing phones etc.
                                       # are there; we just want to copy them
                                       # as the phoneset is the same.
rm data/local/dict${dict_suffix}_larger/lexicon.txt  # we don't want this.
rm data/local/dict${dict_suffix}_larger/lexiconp.txt # we don't want this either.
mincount=2 # Minimum count of an OOV we will try to generate a pron for.

[ ! -f data/local/dict${dict_suffix}/cmudict/cmudict.0.7a ] && \
  echo "CMU dict not in expected place" && exit 1;

# Remove comments from cmudict; print first field; remove
# words like FOO(1) which are alternate prons: our dict format won't
# include these markers.
grep -v ';;;' data/local/dict${dict_suffix}/cmudict/cmudict.0.7a |
 perl -ane 's/^(\S+)\(\d+\)/$1/; print; ' | sort | uniq > $dir/dict.cmu

cat $dir/dict.cmu | awk '{print $1}' | sort | uniq > $dir/wordlist.cmu

echo "Getting training data [this should take at least a few seconds; if not, there's a problem]"

# Convert to uppercase, remove XML-like markings.
# For words ending in "." that are not in CMUdict, we assume that these
# are periods that somehow remained in the data during data preparation,
# and we we replace the "." with "\n".  Note: we found this by looking at
# oov.counts below (before adding this rule).

touch $dir/cleaned.gz
if [ `du -m $dir/cleaned.gz | cut -f 1` -eq 73 ]; then
  echo "Not getting cleaned data in $dir/cleaned.gz again [already exists]";
else
 gunzip -c $srcdir/wsj1/doc/lng_modl/lm_train/np_data/{87,88,89}/*.z \
  | awk '/^</{next}{print toupper($0)}' | perl -e '
   open(F, "<$ARGV[0]")||die;
   while(<F>){ chop; $isword{$_} = 1; }
   while(<STDIN>) {
    @A = split(" ", $_);
    for ($n = 0; $n < @A; $n++) {
      $a = $A[$n];
      if (! $isword{$a} && $a =~ s/^([^\.]+)\.$/$1/) { # nonwords that end in "."
         # and have no other "." in them: treat as period.
         print "$a";
         if ($n+1 < @A) { print "\n"; }
      } else { print "$a "; }
    }
    print "\n";
  }
 ' $dir/wordlist.cmu | gzip -c > $dir/cleaned.gz
fi

# get unigram counts
echo "Getting unigram counts"
gunzip -c $dir/cleaned.gz | tr -s ' ' '\n' | \
  awk '{count[$1]++} END{for (w in count) { print count[w], w; }}' | sort -nr > $dir/unigrams

cat $dir/unigrams | awk -v dict=$dir/dict.cmu \
  'BEGIN{while(getline<dict) seen[$1]=1;} {if(!seen[$2]){print;}}' \
   > $dir/oov.counts

echo "Most frequent unseen unigrams are: "
head $dir/oov.counts

# Prune away singleton counts, and remove things with numbers in
# (which should have been normalized) and with no letters at all.


cat $dir/oov.counts | awk -v thresh=$mincount '{if ($1 >= thresh) { print $2; }}' \
  | awk '/[0-9]/{next;} /[A-Z]/{print;}' > $dir/oovlist

# Automatic rule-finding...

# First make some prons for possible acronyms.
# Note: we don't do this for things like U.K or U.N,
# or A.B. (which doesn't exist anyway),
# as we consider this normalization/spelling errors.

cat $dir/oovlist | local/dict/get_acronym_prons.pl $dir/dict.cmu  > $dir/dict.acronyms

mkdir $dir/f $dir/b # forward, backward directions of rules...
  # forward is normal suffix
  # rules, backward is reversed (prefix rules).  These
  # dirs contain stuff we create while making the rule-based
  # extensions to the dictionary.

# Remove ; and , from words, if they are present; these
# might crash our scripts, as they are used as separators there.
filter_dict.pl $dir/dict.cmu > $dir/f/dict
cat $dir/oovlist | filter_dict.pl > $dir/f/oovs
reverse_dict.pl $dir/f/dict > $dir/b/dict
reverse_dict.pl $dir/f/oovs > $dir/b/oovs

# The next stage takes a few minutes.
# Note: the forward stage takes longer, as English is
# mostly a suffix-based language, and there are more rules
# that it finds.
for d in $dir/f $dir/b; do
 (
   cd $d
   cat dict | get_rules.pl 2>get_rules.log >rules
   get_rule_hierarchy.pl rules >hierarchy
   awk '{print $1}' dict | get_candidate_prons.pl rules dict | \
     limit_candidate_prons.pl hierarchy | \
     score_prons.pl dict | \
     count_rules.pl >rule.counts
   # the sort command below is just for convenience of reading.
   score_rules.pl <rule.counts | sort -t';' -k3,3 -n -r >rules.with_scores
   get_candidate_prons.pl rules.with_scores dict oovs | \
     limit_candidate_prons.pl hierarchy > oovs.candidates
 )  &
done
wait

# Merge the candidates.
reverse_candidates.pl $dir/b/oovs.candidates | cat - $dir/f/oovs.candidates | sort > $dir/oovs.candidates
select_candidate_prons.pl <$dir/oovs.candidates | awk -F';' '{printf("%s  %s\n", $1, $2);}' \
  > $dir/dict.oovs

cat $dir/dict.acronyms $dir/dict.oovs | sort | uniq > $dir/dict.oovs_merged

awk '{print $1}' $dir/dict.oovs_merged | uniq > $dir/oovlist.handled
sort $dir/oovlist | diff - $dir/oovlist.handled  | grep -v 'd' | sed 's:< ::' > $dir/oovlist.not_handled


# add_counts.pl attaches to original counts to the list of handled/not-handled OOVs
add_counts.pl $dir/oov.counts $dir/oovlist.handled | sort -nr > $dir/oovlist.handled.counts
add_counts.pl $dir/oov.counts $dir/oovlist.not_handled | sort -nr > $dir/oovlist.not_handled.counts

echo "**Top OOVs we handled are:**";
head $dir/oovlist.handled.counts
echo "**Top OOVs we didn't handle are as follows (note: they are mostly misspellings):**";
head $dir/oovlist.not_handled.counts


echo "Count of OOVs we handled is `awk '{x+=$1} END{print x}' $dir/oovlist.handled.counts`"
echo "Count of OOVs we couldn't handle is `awk '{x+=$1} END{print x}' $dir/oovlist.not_handled.counts`"
echo "Count of OOVs we didn't handle due to low count is" \
    `awk -v thresh=$mincount '{if ($1 < thresh) x+=$1; } END{print x;}' $dir/oov.counts`
# The two files created above are for humans to look at, as diagnostics.

cat <<EOF | cat - $dir/dict.cmu $dir/dict.oovs_merged | sort | uniq > $dir/lexicon.txt
!SIL SIL
<SPOKEN_NOISE> SPN
<UNK> SPN
<NOISE> SPN
EOF

echo "Created $dir/lexicon.txt"
