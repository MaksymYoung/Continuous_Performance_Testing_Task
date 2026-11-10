// perf-common.groovy - helpers shared by the JMeter / Gatling / Lighthouse Jenkinsfiles.
// Deployed to /var/jenkins_home/perf_common/ by the deploy_*_ubuntu.sh scripts and loaded with
// `load` in the 'Init' stage of each pipeline. Runs as a normal (sandboxed) pipeline script, so
// sh / archiveArtifacts / publishHTML / env are available directly.

/**
 * Resolves every build parameter and exports it as an environment variable.
 *   p        - the `params` object of the pipeline
 *   defaults - [NAME: 'default'] map declared once at the top of the Jenkinsfile
 * An empty or missing value (e.g. the very first build, before Jenkins has registered the
 * parameters) falls back to the default. A parameter whose default is a number must stay a
 * non-negative integer; anything else (e.g. APP) is treated as free text.
 */
def exportParams(p, Map defaults) {
    for (e in defaults.entrySet()) {
        String key = e.key
        String val = (p[key] ?: e.value).toString().trim()
        if ((e.value.toString() ==~ /\d+/) && !(val ==~ /\d+/)) {
            error("Parameter ${key} must be a non-negative integer, got '${val}'")
        }
        env."${key}" = val
    }
}

/**
 * Pre-flight check: fail fast instead of running minutes of 100% errors.
 *   url    - address to request (as seen from the Jenkins container)
 *   host   - optional Host header (the WordPress app redirects unless it is "localhost")
 *   expect - optional text that must be present in the response body
 *   strict - true (default): anything but HTTP 200 fails; false: only a warning
 * Values go in through environment variables, never through string interpolation into the shell.
 */
def checkTarget(Map c) {
    withEnv([
        "CT_URL=${c.url}",
        "CT_HOST=${c.host ?: ''}",
        "CT_EXPECT=${c.expect ?: ''}",
        "CT_STRICT=${c.strict == false ? 0 : 1}"
    ]) {
        sh '''#!/bin/bash
set -uo pipefail
echo "Checking $CT_URL${CT_HOST:+ (Host: $CT_HOST)} from inside the Jenkins container ..."
CT_HOST="${CT_HOST:-}"
CT_STRICT="${CT_STRICT:-1}"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
CODE=$(curl -s -o "$BODY_FILE" -w '%{http_code}' ${CT_HOST:+-H "Host: $CT_HOST"} --connect-timeout 5 --max-time 10 "$CT_URL" || true)
if [ -z "$CODE" ] || [ "$CODE" = "000" ]; then
  echo "ERROR: $CT_URL is not reachable from the container (connection refused/blocked or host not resolved)."
  echo "Set the APP / APP_PORT build parameters to an address that works from inside the container (Docker host gateway, e.g. 172.17.0.1)."
  exit 1
fi
echo "Target responded with HTTP $CODE"
if [ "$CODE" != "200" ]; then
  if [ "$CT_STRICT" = 1 ]; then echo "ERROR: expected HTTP 200, got $CODE"; exit 1; fi
  echo "WARNING: expected HTTP 200, got $CODE"
fi
# withEnv does not define variables with an empty value, so optional ones are read with :-
CT_EXPECT="${CT_EXPECT:-}"
if [ -n "$CT_EXPECT" ]; then
  grep -qF -- "$CT_EXPECT" "$BODY_FILE" || { echo "ERROR: the page does not contain '$CT_EXPECT'"; exit 1; }
  echo "Page content is OK"
fi
'''
    }
}

/**
 * Optionally packs big result folders into .tar.gz files, then archives the whole run folder.
 *   runDir - results/build-N (relative to the workspace); only this build's folder is archived
 *   packs  - list of [archive: 'x.tar.gz', glob: 'folder*', remove: false] maps (remove = delete the
 *            originals after packing; leave false for a folder that publishHTML still needs)
 */
def packAndArchive(String runDir, List packs = []) {
    for (p in packs) {
        withEnv([
            "PK_RUN_DIR=${runDir}",
            "PK_ARCHIVE=${p.archive}",
            "PK_GLOB=${p.glob}",
            "PK_REMOVE=${p.remove ? 1 : 0}"
        ]) {
            sh '''#!/bin/bash
cd "$WORKSPACE/$PK_RUN_DIR" 2>/dev/null || exit 0
# $PK_GLOB is intentionally unquoted: it may be a wildcard
ls -d $PK_GLOB >/dev/null 2>&1 || exit 0
tar czf "$PK_ARCHIVE" $PK_GLOB
[ "$PK_REMOVE" = 1 ] && rm -rf $PK_GLOB
exit 0
'''
        }
    }
    archiveArtifacts artifacts: "${runDir}/**", allowEmptyArchive: true, fingerprint: true
}

/**
 * Adds the HTML report link to the left menu of the build page (needs the "HTML Publisher" plugin).
 *   dir   - folder that contains the report (relative to the workspace)
 *   index - main file of the report
 *   name  - link title
 */
def publishHtmlReport(Map c) {
    try {
        if (!fileExists("${c.dir}/${c.index}")) {
            echo "${c.name}: ${c.dir}/${c.index} not found; skipping HTML publication."
            return
        }
        publishHTML(target: [
            reportDir: c.dir,
            reportFiles: c.index,
            reportName: c.name,
            keepAll: true,
            alwaysLinkToLastBuild: true,
            allowMissing: false
        ])
    } catch (Throwable t) {
        echo "publishHTML is not available (install the HTML Publisher plugin): ${t.message}"
    }
}

return this
