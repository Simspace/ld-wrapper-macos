#!/bin/bash

mkdir panic
cd panic

cat > package.yaml <<- EOM
name: panic

dependencies:
- base
- template-haskell

library:
  source-dirs: src/
  dependencies:
EOM

cat > stack.yaml <<- EOM
resolver: lts-10.7

packages:
- .
EOM

mkdir src

cat > src/Lib.hs <<- EOM
{-# LANGUAGE TemplateHaskell #-}

module Lib where

import Th

foo :: IO ()
foo = pure \$(bar)
EOM

cat > src/Th.hs <<- EOM
{-# LANGUAGE TemplateHaskell #-}

module Th where

import Language.Haskell.TH

bar :: ExpQ
bar = [| () |]
EOM

for i in `seq 1 750`; do
  printf -v iPadded "%0115d" $i
  NAME="module$iPadded"

  mkdir $NAME
  mkdir $NAME/src

  cat > $NAME/package.yaml <<- EOM
name: $NAME
dependencies:
  - base
library:
  source-dirs: src/
EOM

  cat > $NAME/src/Lib$i.hs <<- EOM
module Lib$i (foo) where

foo :: ()
foo = ()
EOM

  echo "  - $NAME" >> package.yaml
  echo "- $NAME" >> stack.yaml

done
