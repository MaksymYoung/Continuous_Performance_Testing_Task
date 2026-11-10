#!/bin/bash
# Deploys the Lighthouse project to the Jenkins container (Ubuntu, native Docker Engine).
# Run from the project folder (where performance-testing-essentials.js, aggregate-lighthouse.js, templates/ and Jenkinsfile are):
#   chmod +x deploy_lighthouse_ubuntu.sh && ./deploy_lighthouse_ubuntu.sh
#
# Optional - also configure Jenkins (HTML Publisher plugin, CSP, job) and start a build:
#   JENKINS_USER=admin JENKINS_PASSWORD='your-password-or-api-token' ./deploy_lighthouse_ubuntu.sh
#   JENKINS_USER=admin JENKINS_PASSWORD='admin' RUN_BUILD=1 ./deploy_lighthouse_ubuntu.sh

JENKINS_CONTAINER="${JENKINS_CONTAINER:-my-jenkins-no-csrf}"
JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JOB_NAME="${JOB_NAME:-lighthouse-performance}"
NODE_VERSION="${NODE_VERSION:-20.18.1}"   # Node 18+ is required; lighthouse 9 / puppeteer 13 are happiest on 18/20
APP_HOST="${APP_HOST:-172.17.0.1}"        # application address as seen from the Jenkins container
APP_PORT="${APP_PORT:-80}"
SET_CSP="${SET_CSP:-1}"                   # 1 = allow JavaScript in HTML reports (needs credentials; lost on Jenkins restart)
RUN_BUILD="${RUN_BUILD:-0}"               # 1 = start a build at the end (needs credentials)
DEST="/var/jenkins_home/lighthouse_project"
SRC="$(cd "$(dirname "$0")" && pwd)"

AUTH_OK=0
if [ -n "$JENKINS_USER" ] && [ -n "$JENKINS_PASSWORD" ]; then AUTH_OK=1; fi

# curl wrapper for the Jenkins API: adds credentials and, when CSRF protection is on, a crumb
CRUMB_HEADER=""
jcurl() { curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" ${CRUMB_HEADER:+-H "$CRUMB_HEADER"} "$@"; }
get_crumb() {
  local c
  c=$(curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" "$JENKINS_URL/crumbIssuer/api/json" 2>/dev/null)
  CRUMB_HEADER=$(printf '%s' "$c" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d["crumbRequestField"]+":"+d["crumb"])
except Exception:
    pass' 2>/dev/null)
}

echo '_________________________________'
echo "######## STEP 0 ################"
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not available"
  exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -qx "$JENKINS_CONTAINER"; then
  echo "Container $JENKINS_CONTAINER is not running, starting it..."
  docker start "$JENKINS_CONTAINER" || { echo "ERROR: cannot start $JENKINS_CONTAINER"; exit 1; }
  sleep 5
fi
for f in performance-testing-essentials.js aggregate-lighthouse.js package.json Jenkinsfile; do
  [ -f "$SRC/$f" ] || { echo "ERROR: $f not found in $SRC"; exit 1; }
done
[ -d "$SRC/templates" ] || { echo "ERROR: folder templates/ not found in $SRC"; exit 1; }
echo "Jenkins container: $JENKINS_CONTAINER - running"

# Shared pipeline helpers (the Jenkinsfile loads them with `load`)
COMMON_SRC="${COMMON_SRC:-$SRC/../perf-common.groovy}"
[ -f "$COMMON_SRC" ] || { echo "ERROR: perf-common.groovy not found ($COMMON_SRC)"; exit 1; }
docker exec -u root "$JENKINS_CONTAINER" mkdir -p /var/jenkins_home/perf_common || exit 1
docker cp "$COMMON_SRC" "$JENKINS_CONTAINER:/var/jenkins_home/perf_common/perf-common.groovy" || { echo "ERROR: cannot copy perf-common.groovy"; exit 1; }
docker exec -u root "$JENKINS_CONTAINER" chown -R jenkins:jenkins /var/jenkins_home/perf_common
echo "Shared helpers: perf-common.groovy copied"

echo '_________________________________'
echo "######## STEP 1 ################"
echo "Checking Node.js (18+) and the system libraries for Chromium in the container"
NODE_MAJOR=$(docker exec "$JENKINS_CONTAINER" bash -c "node --version 2>/dev/null | sed 's/^v//; s/\..*//'")
if [ -n "$NODE_MAJOR" ] && [ "$NODE_MAJOR" -ge 18 ] 2>/dev/null; then
  echo "Node.js v$NODE_MAJOR is already installed"
else
  case "$(docker exec "$JENKINS_CONTAINER" uname -m)" in
    x86_64)  NODE_ARCH=x64 ;;
    aarch64) NODE_ARCH=arm64 ;;
    *) echo "ERROR: unsupported CPU architecture"; exit 1 ;;
  esac
  echo "Installing Node.js $NODE_VERSION ($NODE_ARCH) into /opt/node (needs internet access from the container)..."
  docker exec -i -u root "$JENKINS_CONTAINER" bash -s <<EOF || { echo "ERROR: Node.js installation failed"; exit 1; }
set -e
cd /opt
rm -rf node "node-v$NODE_VERSION-linux-$NODE_ARCH"
curl -fLO "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
tar xzf "node-v$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
rm -f "node-v$NODE_VERSION-linux-$NODE_ARCH.tar.gz"
ln -s "node-v$NODE_VERSION-linux-$NODE_ARCH" node
ln -sf /opt/node/bin/node /usr/local/bin/node
ln -sf /opt/node/bin/npm /usr/local/bin/npm
ln -sf /opt/node/bin/npx /usr/local/bin/npx
EOF
fi
docker exec "$JENKINS_CONTAINER" bash -c "echo node \$(node --version), npm \$(npm --version)" || { echo "ERROR: node not working in the container"; exit 1; }

# Chromium (downloaded by puppeteer) needs a set of shared libraries that the Jenkins image does not have
if docker exec "$JENKINS_CONTAINER" bash -c "command -v apt-get >/dev/null"; then
  echo "Installing system libraries for Chromium (apt-get)..."
  docker exec -i -u root "$JENKINS_CONTAINER" bash -s <<'EOF' || { echo "ERROR: apt-get install failed"; exit 1; }
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
PKGS="ca-certificates fonts-liberation libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libgbm1 libnspr4 libnss3 \
libpango-1.0-0 libcairo2 libx11-6 libxcb1 libxcomposite1 libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 libxshmfence1"
apt-get install -y --no-install-recommends $PKGS
apt-get install -y --no-install-recommends libasound2 || apt-get install -y --no-install-recommends libasound2t64
EOF
else
  echo "WARNING: apt-get not found in the container (not Debian/Ubuntu based) - install the Chromium libraries manually."
fi
echo "Node.js + libraries: Done!"

echo '_________________________________'
echo "######## STEP 2 ################"
echo "Copying the project to $JENKINS_CONTAINER:$DEST (node_modules is kept between deploys)"
docker exec -u root "$JENKINS_CONTAINER" bash -c "mkdir -p '$DEST' && cd '$DEST' && rm -rf templates performance-testing-essentials.js aggregate-lighthouse.js package.json" || exit 1
tar -C "$SRC" -cf - performance-testing-essentials.js aggregate-lighthouse.js package.json templates \
  | docker exec -i -u root "$JENKINS_CONTAINER" tar -C "$DEST" -xf - || { echo "ERROR: copy failed"; exit 1; }
docker exec -u root "$JENKINS_CONTAINER" chown -R jenkins:jenkins "$DEST"
docker exec "$JENKINS_CONTAINER" ls -la "$DEST"
echo "Copy: Done!"

echo '_________________________________'
echo "######## STEP 3 ################"
echo "Installing lighthouse 9.x and puppeteer 13.x (with its Chromium) as user jenkins - the first time takes a few minutes"
docker exec -u jenkins -w "$DEST" "$JENKINS_CONTAINER" npm install --no-audit --no-fund \
  || { echo "ERROR: npm install failed (is the internet reachable from the container?)"; exit 1; }
docker exec -u jenkins -w "$DEST" "$JENKINS_CONTAINER" test -f node_modules/lighthouse/lighthouse-core/fraggle-rock/api.js \
  || { echo "ERROR: lighthouse-core/fraggle-rock/api.js not found - wrong lighthouse version installed"; exit 1; }

echo "Smoke test: starting Chromium inside the container"
docker exec -u jenkins -w "$DEST" "$JENKINS_CONTAINER" node -e "
const puppeteer = require('puppeteer');
(async () => {
  const b = await puppeteer.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'] });
  console.log('Chromium started: ' + await b.version());
  await b.close();
})().catch(e => { console.error('Chromium failed: ' + e.message); process.exit(1); });
" || { echo "ERROR: Chromium does not start (missing libraries? see the message above)"; exit 1; }
echo "Lighthouse + Chromium: Done!"

echo '_________________________________'
echo "######## STEP 4 ################"
echo "Checking the application from inside the Jenkins container ($APP_HOST:$APP_PORT, Host: localhost)"
CODE=$(docker exec "$JENKINS_CONTAINER" curl -s -o /dev/null -w '%{http_code}' -H "Host: localhost" --connect-timeout 5 --max-time 10 "http://$APP_HOST:$APP_PORT/")
echo "HTTP response code is $CODE"
if [ "$CODE" != "200" ]; then
  echo "ALARM: the app is not reachable (or not answering 200) from the Jenkins container. Is the wp container running (docker ps)?"
  echo "If the Docker host gateway is not $APP_HOST, check it and fix the APP default in the Jenkinsfile (or the APP build parameter):"
  docker exec "$JENKINS_CONTAINER" bash -c "getent hosts host.docker.internal; ip route 2>/dev/null | grep default"
  exit 1
fi
if ! grep -qE "APP: *'$APP_HOST'" "$SRC/Jenkinsfile"; then
  echo "WARNING: the APP default (DEFAULTS map) in the Jenkinsfile is not '$APP_HOST' - make sure it points to an address that works from the container."
fi

echo '_________________________________'
echo "######## STEP 5 ################"
if [ "$AUTH_OK" = "1" ]; then
  echo "Configuring Jenkins at $JENKINS_URL"
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -u "$JENKINS_USER:$JENKINS_PASSWORD" "$JENKINS_URL/api/json")
  if [ "$CODE" != "200" ]; then
    echo "ERROR: cannot log in to Jenkins (HTTP $CODE). Check JENKINS_URL, JENKINS_USER and JENKINS_PASSWORD."
    exit 1
  fi
  get_crumb

  # --- HTML Publisher plugin ---
  if jcurl "$JENKINS_URL/pluginManager/api/json?depth=1&tree=plugins%5BshortName%5D" | grep -q '"shortName":"htmlpublisher"'; then
    echo "Plugin HTML Publisher is already installed"
  else
    echo "Installing the HTML Publisher plugin (needs internet access from Jenkins)..."
    R=$(jcurl -o /dev/null -w '%{http_code}' -H "Content-Type: text/xml" \
        --data '<jenkins><install plugin="htmlpublisher@current"/></jenkins>' "$JENKINS_URL/pluginManager/installNecessaryPlugins")
    echo "Jenkins responded with HTTP $R (200/302 = accepted)"
    for i in $(seq 1 30); do
      if jcurl "$JENKINS_URL/pluginManager/api/json?depth=1&tree=plugins%5BshortName%5D" | grep -q '"shortName":"htmlpublisher"'; then
        echo "HTML Publisher installed"; break
      fi
      sleep 5
    done
    jcurl "$JENKINS_URL/pluginManager/api/json?depth=1&tree=plugins%5BshortName%5D" | grep -q '"shortName":"htmlpublisher"' \
      || echo "WARNING: HTML Publisher is not installed yet - install it manually (Manage Jenkins -> Plugins). The report stays available as an artifact."
  fi

  # --- CSP for HTML reports ---
  if [ "$SET_CSP" = "1" ]; then
    jcurl -o /dev/null --data-urlencode 'script=System.setProperty("hudson.model.DirectoryBrowserSupport.CSP", "")' "$JENKINS_URL/scriptText"
    echo "CSP for archived HTML reports relaxed (lab only; the setting is lost when Jenkins restarts - run this script again then)."
  fi

  # --- job ---
  echo "Creating/updating Jenkins job '$JOB_NAME'"
  CONFIG_XML="$(mktemp)"
  python3 - "$SRC/Jenkinsfile" "$CONFIG_XML" <<'PYEOF'
import sys
from xml.sax.saxutils import escape
script = open(sys.argv[1], encoding="utf-8").read()
xml = f"""<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Lighthouse user flow (performance-testing-essentials.js)</description>
  <keepDependencies>false</keepDependencies>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>{escape(script)}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
"""
open(sys.argv[2], "w", encoding="utf-8").write(xml)
PYEOF
  EXISTS=$(jcurl -o /dev/null -w '%{http_code}' "$JENKINS_URL/job/$JOB_NAME/api/json")
  if [ "$EXISTS" = "200" ]; then
    R=$(jcurl -o /dev/null -w '%{http_code}' -H "Content-Type: application/xml" \
        --data-binary @"$CONFIG_XML" "$JENKINS_URL/job/$JOB_NAME/config.xml")
  else
    R=$(jcurl -o /dev/null -w '%{http_code}' -H "Content-Type: application/xml" \
        --data-binary @"$CONFIG_XML" "$JENKINS_URL/createItem?name=$JOB_NAME")
  fi
  rm -f "$CONFIG_XML"
  echo "Jenkins responded with HTTP $R (200 = OK)"
  JOB_OK=0
  [ "$R" = "200" ] && JOB_OK=1
  [ "$JOB_OK" = "1" ] || echo "WARNING: job was not created automatically - create it manually (see below)."

  # --- optional build ---
  if [ "$RUN_BUILD" = "1" ] && [ "$JOB_OK" = "1" ]; then
    R=$(jcurl -o /dev/null -w '%{http_code}' -X POST "$JENKINS_URL/job/$JOB_NAME/build")
    echo "Build started (HTTP $R, 201 = queued). The test takes about 10-15 minutes."
  fi
else
  echo "JENKINS_USER / JENKINS_PASSWORD are not set - skipping HTML Publisher, CSP and job configuration."
fi

echo '_________________________________'
echo "Deploy: Done! :)"
if [ "$AUTH_OK" = "1" ]; then
  echo "Job:           $JENKINS_URL/job/$JOB_NAME/"
  echo "Latest report: $JENKINS_URL/job/$JOB_NAME/Lighthouse_20Report/   (after the first successful build)"
else
  echo "Next: $JENKINS_URL -> Manage Jenkins -> Plugins -> install 'HTML Publisher'"
  echo "      $JENKINS_URL -> New Item -> Pipeline -> '$JOB_NAME' -> Definition: Pipeline script -> paste ./Jenkinsfile -> Save -> Build Now"
  echo "      (Script Console, to see charts in the report: System.setProperty(\"hudson.model.DirectoryBrowserSupport.CSP\", \"\"))"
fi
echo "The test runs about 10-15 minutes: 10 loops of the order flow (7 steps each) + a 5 s pause between loops."
