# Install dependencies
install:
    mise install
    pnpm install
    perl Build.PL
    ./Build installdeps

build-data:
    ./scripts/preprocess_gramps_db

css:
    pnpm build:css

typescript:
    pnpm build:ts

# Build the project
build: install
    ./Build
    pnpm build:css
    pnpm build:ts
    mkdir -p public/images/HPNOFP
    find share/HPNOFP/src/OEBPS/ \( -name '*.jpg' -o -name '*.gif' \) -exec cp "{}" public/images/HPNOFP/ \;

tidy:
    find lib -name '*.pm' -exec perltidy -b -pro=.perltidyrc {} \;
    find t -name '*.t' -exec perltidy -b -pro=.perltidyrc {} \;
    perltidy -b -pro=.perltidyrc Build.PL
    perltidy -b -pro=.perltidyrc bin/server.pl
    find . -name '*.bak' -delete

# Run tests
test:
    ./Build test
    pnpm test

# Clean build artifacts
clean:
    ./Build clean
    pnpm run clean

# Development server
dev: build build-data
    perl bin/server.pl

quickdev:
    watchexec -w bin -w lib -w ../PAGI-WebServer/lib -w templates -w public/css -w public/js -w share/pages -w share/Bookmarks -w share/history -w share/HPNOFP -r ./bin/server.pl

# Production server
prod: build build-data
    ./Build && perl bin/server.pl --mode production

# Deploy to development environment
deploy-dev: install build-data build
    pnpm cdk --profile personal acknowledge 34892
    MODE='dev' pnpm cdk --profile personal deploy

# Deploy to production environment
deploy-prod: install build-data build
    pnpm cdk --profile personal acknowledge 34892
    MODE='prod' pnpm cdk --profile personal deploy
