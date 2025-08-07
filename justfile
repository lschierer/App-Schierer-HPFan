tidy:
  find lib t -name '*.pm' -exec perltidy -b -pro=.perltidyrc {} \;
  perltidy -b -pro=.perltidyrc Build.PL
  perltidy -b -pro=.perltidyrc bin/app_schierer_hpfan
  find . -name '*.bak' -delete

install:
  mise trust
  mise install
  pnpm install
  perl Build.PL
  ./Build installdeps
  mkdir -p public/images/HPNOFP
  find share/HPNOFP/src/OEBPS/ \( -name '*.jpg' -o -name '*.gif' \) -exec cp "{}" public/images/HPNOFP/ \;

css:
  pnpm build:css

ts:
  pnpm build:ts

build: install css ts
  ./Build manifest
  ./Build

quickdev:
  morbo -w templates -w share -w public -w lib ./bin/app_schierer_hpfan prefork
