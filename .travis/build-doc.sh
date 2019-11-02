#!/bin/bash
set -e

source .travis/logger.sh
source .travis/common-functions.sh

VERSION=$(./mvnw -q -Dexec.executable="echo" -Dexec.args='${project.version}' --non-recursive org.codehaus.mojo:exec-maven-plugin:1.5.0:exec)
log_info "Building PMD Documentation ${VERSION} on branch ${TRAVIS_BRANCH}"

#
# First step: build pmd with profile "generate-rule-docs"
# The docs should appear under "docs/pages/rules/..." for each language
#
./mvnw clean verify -Dmaven.test.skip=true -Dmaven.javadoc.skip=true -P generate-rule-docs



if ! travis_isPush; then
    log_info "Not publishing site, since this is not a push!"
    exit 0
fi



pushd docs

# run jekyll
echo -e "\n\n"
log_info "Building documentation using jekyll..."
bundle install
bundle exec jekyll build

# create pmd-doc archive
echo -e "\n\n"
log_info "Creating pmd-doc archive..."
mv _site pmd-doc-${VERSION}
zip -qr pmd-doc-${VERSION}.zip pmd-doc-${VERSION}/
log_success "Successfully created pmd-doc-${VERSION}.zip:"
ls -lh pmd-doc-${VERSION}.zip

popd

if [[ "${VERSION}" != *-SNAPSHOT && "${TRAVIS_TAG}" != "" ]]; then
    # Deploy to github releases
    RELEASE_ID=$(curl -s -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" 'https://api.github.com/repos/pmd/pmd/releases?per_page=1'|jq ".[0].id")
    RELEASE_DATA=$(curl -s -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" "https://api.github.com/repos/pmd/pmd/releases/${RELEASE_ID}")
    DRAFT=$(echo "$RELEASE_DATA"|jq ".draft")
    if [ "$DRAFT" != "true" ]; then
        REQUEST=$(cat <<EOF
{
    "tag_name": "${TRAVIS_TAG}",
    "target_commitish": "$(git show-ref --hash HEAD)",
    "name": "${TRAVIS_TAG}",
    "draft": true
}
EOF
        )
        RELEASE_ID=$(curl -s -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" -H "Content-Type: application/json" \
            --data "${REQUEST}" -X POST https://api.github.com/repos/pmd/pmd/releases | jq ".id")
        echo $RELEASE_ID
        log_info "Created draft release with id ${RELEASE_ID}"
    else
        log_info "Using draft release with id "${RELEASE_ID}"
    fi
    UPLOAD_URL=$(echo "$RELEASE_DATA" | jq --raw-output ".upload_url")
    UPLOAD_URL=${UPLOAD_URL%%\{\?name,label\}}
    echo "Uploading docs/pmd-doc-${VERSION}.zip ..."
    curl -s -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" -H "Content-Type: application/zip" \
        --data-binary "@docs/pmd-doc-${VERSION}.zip" \
        -X POST "${UPLOAD_URL}?name=pmd-doc-${VERSION}.zip"
    
    # updating github release text
    # renders, and skips the first 6 lines - the Jekyll front-matter
    RENDERED_RELEASE_NOTES=$(bundle exec .travis/render_release_notes.rb docs/pages/release_notes.md | tail -n +6)
    
    # Assumes, the release has already been created by travis github releases provider
    RELEASE_NAME="PMD ${VERSION} ($(date -u +%d-%B-%Y))"
    RELEASE_BODY="$RENDERED_RELEASE_NOTES"
    RELEASE_BODY="${RELEASE_BODY//'\'/\\\\}"
    RELEASE_BODY="${RELEASE_BODY//$'\r'/}"
    RELEASE_BODY="${RELEASE_BODY//$'\n'/\\r\\n}"
    RELEASE_BODY="${RELEASE_BODY//'"'/\\\"}"
    cat > release-edit-request.json <<EOF
    {
      "name": "$RELEASE_NAME",
      "body": "$RELEASE_BODY"
    }
    EOF
    echo -e "\n\n"
    log_info "Updating release at https://api.github.com/repos/pmd/pmd/releases/${RELEASE_ID}..."
    
    
    RESPONSE=$(curl -i -s -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" -H "Content-Type: application/json" --data "@release-edit-request.json" -X PATCH https://api.github.com/repos/pmd/pmd/releases/${RELEASE_ID})
    if [[ "$RESPONSE" != *"HTTP/1.1 200"* ]]; then
        log_error "Github Request failed!"
        echo "Request:"
        cat release-edit-request.json
        echo
        echo "Response:"
        echo "$RESPONSE"
    else
        log_success "Update OK"
    fi
    
    echo -e "\n\n"
    log_info "Adding the new doc to pmd.github.io..."
    # clone pmd.github.io. Note: This uses the ssh key setup earlier
    # In order to speed things up, we use a sparse checkout - no need to checkout all directories here
    mkdir pmd.github.io
    (
        cd pmd.github.io
        git init
        git config user.name "Travis CI (pmd-bot)"
        git config user.email "andreas.dangel+pmd-bot@adangel.org"
        git config core.sparsecheckout true
        git remote add origin git@github.com:pmd/pmd.github.io.git
        echo "/latest/" > .git/info/sparse-checkout
        echo "/sitemap.xml" >> .git/info/sparse-checkout
        git pull --depth=1 origin master
        log_info "Copying documentation from ../docs/pmd-doc-${VERSION}/ to pmd-${VERSION}/ ..."
        rsync -ah --stats ../docs/pmd-doc-${VERSION}/ pmd-${VERSION}/
        git status
        echo "Executing: git add pmd-${VERSION}"
        git add pmd-${VERSION}
        echo "Executing: git commit..."
        git commit -q -m "Added pmd-${VERSION}"
    
        log_info "Copying pmd-${VERSION} to latest ..."
        git rm -qr latest
        cp -a pmd-${VERSION} latest
        echo "Executing: git add latest"
        git add latest
        echo "Executing: git commit..."
        git commit -q -m "Copying pmd-${VERSION} to latest"
    
        log_info "Generating sitemap.xml"
        ../.travis/sitemap_generator.sh > sitemap.xml
        echo "Executing: git add sitemap.xml"
        git add sitemap.xml
        echo "Executing: git commit..."
        git commit -q -m "Generated sitemap.xml"
    
        echo "Executing: git push origin master"
        git push origin master
    )


    (
        # disable fast fail, exit immediately, in this subshell
        set +e

        echo -e "\n\n"
        log_info "Uploading the new release to pmd.sourceforge.net which serves as an archive..."
    
        .travis/travis_wait "rsync -ah --stats docs/pmd-doc-${VERSION}/ ${PMD_SF_USER}@web.sourceforge.net:/home/project-web/pmd/htdocs/pmd-${VERSION}/"

        if [ $? -ne 0 ]; then
            log_error "Uploading documentation to pmd.sourceforge.net failed..."
            log_error "Please upload manually (PMD Version: ${VERSION})"
        else
            log_success "The documentation is now available under http://pmd.sourceforge.net/pmd-${VERSION}/"
        fi
        true
    )
fi


# Deploy to sourceforge files
(
    # disable fast fail, exit immediately, in this subshell
    set +e

    if [[ "${TRAVIS_TAG}" != "" || "${VERSION}" == *-SNAPSHOT ]]; then
        echo -e "\n\n"
        log_info "Uploading pmd doc distribution to sourceforge..."
        .travis/travis_wait "rsync -avh docs/pmd-doc-${VERSION}.zip ${PMD_SF_USER}@web.sourceforge.net:/home/frs/project/pmd/pmd/${VERSION}/"
        if [ $? -ne 0 ]; then
            log_error "Couldn't upload docs/pmd-doc-${VERSION}.zip!"
            log_error "Please upload manually: https://sourceforge.net/projects/pmd/files/pmd/"
        else
            log_success "Successfully uploaded pmd-doc-${VERSION}.zip to sourceforge"
        fi
    fi

    # rsync site to pmd.sourceforge.net/snapshot
    if [[ "${VERSION}" == *-SNAPSHOT && "${TRAVIS_BRANCH}" == "master" ]]; then
        echo -e "\n\n"
        log_info "Uploading snapshot site to pmd.sourceforge.net/snapshot..."
        .travis/travis_wait "rsync -ah --stats --delete docs/pmd-doc-${VERSION}/ ${PMD_SF_USER}@web.sourceforge.net:/home/project-web/pmd/htdocs/snapshot/"
        if [ $? -ne 0 ]; then
            log_error "Couldn't upload the snapshot documentation. It won't be current on http://pmd.sourceforge.net/snapshot/"
        else
            log_success "Successfully uploaded snapshot documentation: http://pmd.sourceforge.net/snapshot/"
        fi
    fi

    true
)



#
# Push the generated site to gh-pages branch
# only for snapshot builds from branch master
#
if [[ "${VERSION}" == *-SNAPSHOT && "${TRAVIS_BRANCH}" == "master" ]]; then
    echo -e "\n\n"
    log_info "Pushing the new site to github pages..."
    git clone --branch gh-pages --depth 1 git@github.com:pmd/pmd.git pmd-gh-pages
    # clear the files first
    rm -rf pmd-gh-pages/*
    # copy the new site
    cp -a docs/pmd-doc-${VERSION}/* pmd-gh-pages/
    (
        cd pmd-gh-pages
        git config user.name "Travis CI (pmd-bot)"
        git config user.email "andreas.dangel+pmd-bot@adangel.org"
        git add -A
        MSG="Update documentation

TRAVIS_JOB_NUMBER=${TRAVIS_JOB_NUMBER}
TRAVIS_COMMIT_RANGE=${TRAVIS_COMMIT_RANGE}"
        git commit -q -m "$MSG"
        git push git@github.com:pmd/pmd.git HEAD:gh-pages
        log_success "Successfully pushed site to https://pmd.github.io/pmd/"
    )
fi

