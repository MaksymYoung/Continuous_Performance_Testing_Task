#!/bin/bash
# Deploys the JMeter project to the Jenkins container (Ubuntu, native Docker Engine).
# Run from the project folder (where PerformanceEssentials.jmx, csv/ and Jenkinsfile are):
#   chmod +x deploy_jmeter_ubuntu.sh && ./deploy_jmeter_ubuntu.sh
#
# Optional - also configure Jenkins (HTML Publisher plugin, CSP, job) and start a build:
#   JENKINS_USER=admin JENKINS_PASSWORD='your-password-or-api-token' ./deploy_jmeter_ubuntu.sh
#   JENKINS_USER=admin JENKINS_PASSWORD='admin' RUN_BUILD=1 ./deploy_jmeter_ubuntu.sh

JENKINS_CONTAINER="${JENKINS_CONTAINER:-my-jenkins-no-csrf}"
JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JOB_NAME="${JOB_NAME:-jmeter-performance}"
JMETER_VERSION="${JMETER_VERSION:-5.6.3}"
APP_HOST="${APP_HOST:-172.17.0.1}"     # application address as seen from the Jenkins container
APP_PORT="${APP_PORT:-80}"
SET_CSP="${SET_CSP:-1}"                # 1 = allow JavaScript in HTML reports (needs credentials; lost on Jenkins restart)
RUN_BUILD="${RUN_BUILD:-0}"            # 1 = start a build at the end (needs credentials)
DEST="/var/jenkins_home/perf_project"
JM="/opt/apache-jmeter"
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
[ -f "$SRC/PerformanceEssentials.jmx" ] && [ -f "$SRC/Jenkinsfile" ] || { echo "ERROR: PerformanceEssentials.jmx / Jenkinsfile not found in $SRC"; exit 1; }
[ -d "$SRC/csv" ] || echo "WARNING: folder csv/ not found in $SRC - the test plan needs csv/checkout.csv"
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
echo "Checking JMeter $JMETER_VERSION and the Ultimate Thread Group plugin (jpgc-casutg) in the container"
NEED_JMETER=1
if docker exec "$JENKINS_CONTAINER" test -x "$JM/bin/jmeter"; then
  if docker exec "$JENKINS_CONTAINER" bash -c "'$JM/bin/jmeter' --version 2>&1 | grep -q '$JMETER_VERSION'"; then NEED_JMETER=0; fi
fi
if [ "$NEED_JMETER" = "1" ]; then
  echo "Installing JMeter $JMETER_VERSION into $JM (needs internet access from the container)..."
  docker exec -i -u root "$JENKINS_CONTAINER" bash -s <<EOF || { echo "ERROR: JMeter installation failed"; exit 1; }
set -e
cd /opt
rm -rf "apache-jmeter-$JMETER_VERSION" apache-jmeter
curl -fLO "https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-$JMETER_VERSION.tgz"
tar xzf "apache-jmeter-$JMETER_VERSION.tgz"
rm -f "apache-jmeter-$JMETER_VERSION.tgz"
ln -s "apache-jmeter-$JMETER_VERSION" apache-jmeter
curl -fL -o apache-jmeter/lib/ext/jmeter-plugins-manager-1.10.jar https://repo1.maven.org/maven2/kg/apc/jmeter-plugins-manager/1.10/jmeter-plugins-manager-1.10.jar
curl -fL -o apache-jmeter/lib/cmdrunner-2.3.jar https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar
java -cp apache-jmeter/lib/ext/jmeter-plugins-manager-1.10.jar org.jmeterplugins.repository.PluginManagerCMDInstaller
EOF
else
  echo "JMeter $JMETER_VERSION is already installed"
fi
if ! docker exec "$JENKINS_CONTAINER" bash -c "ls '$JM/lib/ext' | grep -qi casutg"; then
  echo "Installing the Ultimate Thread Group plugin (jpgc-casutg)..."
  docker exec -u root "$JENKINS_CONTAINER" "$JM/bin/PluginsManagerCMD.sh" install jpgc-casutg || { echo "ERROR: plugin installation failed"; exit 1; }
else
  echo "Plugin jpgc-casutg is already installed"
fi
docker exec "$JENKINS_CONTAINER" bash -c "ls '$JM/lib/ext' | grep -i casutg" || { echo "ERROR: jpgc-casutg not found after installation"; exit 1; }
echo "JMeter: Done!"

echo '_________________________________'
echo "######## STEP 2 ################"
echo "Copying the project to $JENKINS_CONTAINER:$DEST"
docker exec -u root "$JENKINS_CONTAINER" bash -c "rm -rf '$DEST' && mkdir -p '$DEST'" || exit 1
ITEMS="PerformanceEssentials.jmx"
[ -d "$SRC/csv" ] && ITEMS="$ITEMS csv"
# shellcheck disable=SC2086
tar -C "$SRC" -cf - $ITEMS \
  | docker exec -i -u root "$JENKINS_CONTAINER" tar -C "$DEST" -xf - || { echo "ERROR: copy failed"; exit 1; }
docker exec -u root "$JENKINS_CONTAINER" chown -R jenkins:jenkins "$DEST"
docker exec "$JENKINS_CONTAINER" ls -la "$DEST"
echo "Copy: Done!"

echo '_________________________________'
echo "######## STEP 3 ################"
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
echo "######## STEP 4 ################"
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
  <description>JMeter performance test (PerformanceEssentials.jmx)</description>
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
    echo "Build started (HTTP $R, 201 = queued). The test takes about 10 minutes."
  fi
else
  echo "JENKINS_USER / JENKINS_PASSWORD are not set - skipping HTML Publisher, CSP and job configuration."
fi

echo '_________________________________'
echo "Deploy: Done! :)"
if [ "$AUTH_OK" = "1" ]; then
  echo "Job:           $JENKINS_URL/job/$JOB_NAME/"
  echo "Latest report: $JENKINS_URL/job/$JOB_NAME/JMeter_20Report/   (after the first successful build)"
else
  echo "Next: $JENKINS_URL -> Manage Jenkins -> Plugins -> install 'HTML Publisher'"
  echo "      $JENKINS_URL -> New Item -> Pipeline -> '$JOB_NAME' -> Definition: Pipeline script -> paste ./Jenkinsfile -> Save -> Build Now"
  echo "      (Script Console, to see charts in the report: System.setProperty(\"hudson.model.DirectoryBrowserSupport.CSP\", \"\"))"
fi
echo "The test runs about 10 minutes: 4 virtual users, 30 s ramp-up, 560 s hold, 10 s shutdown."
