#!/bin/bash
set -e


# Build Perl module
perl Build.PL
./Build installdeps --cpan_client 'cpanm -nq --with-recommends'
./Build manifest
./Build

# Build CSS + TypeScript
pnpm install
pnpm build

# Preprocess gramps database
scripts/preprocess_gramps_db

# Copy ebook images to public directory
mkdir -p public/images/HPNOFP
find share/HPNOFP/src/OEBPS/ \( -name '*.jpg' -o -name '*.gif' \) -exec cp "{}" public/images/HPNOFP/ \;
