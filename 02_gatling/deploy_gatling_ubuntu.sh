#!/bin/bash
# Deploys the Gatling project to the Jenkins container (Ubuntu, native Docker Engine).
# Run from the project folder (where pom.xml, src/ and Jenkinsfile are):
#   chmod +x deploy_gatling_ubuntu.sh && ./deploy_gatling_ubuntu.sh
#
# Optional - also configure Jenkins (HTML Publisher plugin, CSP, job) and start a build:
#   JENKINS_USER=admin JENKINS_PASSWORD='your-password-or-api-token' ./deploy_gatling_ubuntu.sh
#   JENKINS_USER=admin JENKINS_PASSWORD='admin' RUN_BUILD=1 ./deploy_gatling_ubuntu.sh

JENKINS_CONTAINER="${JENKINS_CONTAINER:-my-jenkins-no-csrf}"
JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JOB_NAME="${JOB_NAME:-gatling-perf-test}"
APP_HOST="${APP_HOST:-172.17.0.1}"     # application address as seen from the Jenkins container
APP_PORT="${APP_PORT:-80}"
SET_CSP="${SET_CSP:-1}"                # 1 = allow JavaScript in HTML reports (needs credentials; lost on Jenkins restart)
RUN_BUILD="${RUN_BUILD:-0}"            # 1 = start a build at the end (needs credentials)
DEST="/var/jenkins_home/gatling_project"
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
[ -f "$SRC/pom.xml" ] && [ -f "$SRC/Jenkinsfile" ] || { echo "ERROR: pom.xml / Jenkinsfile not found in $SRC"; exit 1; }
echo "Jenkins container: $JENKINS_CONTAINER - running"

echo '_________________________________'
echo "######## STEP 1 ################"
echo "Copying the project to $JENKINS_CONTAINER:$DEST"
docker exec -u root "$JENKINS_CONTAINER" bash -c "rm -rf '$DEST' && mkdir -p '$DEST'" || exit 1
tar -C "$SRC" --exclude=./target --exclude=./.git --exclude=./deploy_gatling_ubuntu.sh -cf - . \
  | docker exec -i -u root "$JENKINS_CONTAINER" tar -C "$DEST" -xf - || { echo "ERROR: copy failed"; exit 1; }
docker exec -u root "$JENKINS_CONTAINER" chown -R jenkins:jenkins "$DEST"
docker exec "$JENKINS_CONTAINER" ls -la "$DEST"
echo "Copy: Done!"

echo '_________________________________'
echo "######## STEP 2 ################"
echo "Checking the application from inside the Jenkins container ($APP_HOST:$APP_PORT, Host: localhost)"
CODE=$(docker exec "$JENKINS_CONTAINER" curl -s -o /dev/null -w '%{http_code}' -H "Host: localhost" --connect-timeout 5 --max-time 10 "http://$APP_HOST:$APP_PORT/")
echo "HTTP response code is $CODE"
if [ "$CODE" != "200" ]; then
  echo "ALARM: the app is not reachable from the Jenkins container. Is the wp container running (docker ps)?"
  echo "If the Docker host gateway is not $APP_HOST, check it and fix APP in the Jenkinsfile:"
  docker exec "$JENKINS_CONTAINER" bash -c "getent hosts host.docker.internal; ip route 2>/dev/null | grep default"
  exit 1
fi
if ! grep -q "APP *= *'$APP_HOST'" "$SRC/Jenkinsfile"; then
  echo "WARNING: APP in the Jenkinsfile is not '$APP_HOST' - make sure it points to an address that works from the container."
fi

echo '_________________________________'
echo "######## STEP 3 ################"
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
  <description>Gatling performance test (PerfTestSimulation)</description>
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
    echo "Build started (HTTP $R, 201 = queued). The test takes about 10 minutes (the first build is longer: JDK 21, Maven and dependencies are downloaded)."
  fi
else
  echo "JENKINS_USER / JENKINS_PASSWORD are not set - skipping HTML Publisher, CSP and job configuration."
fi

echo '_________________________________'
echo "Deploy: Done! :)"
if [ "$AUTH_OK" = "1" ]; then
  echo "Job:           $JENKINS_URL/job/$JOB_NAME/"
  echo "Latest report: $JENKINS_URL/job/$JOB_NAME/Gatling_20Report/   (after the first successful build)"
else
  echo "Next: $JENKINS_URL -> Manage Jenkins -> Plugins -> install 'HTML Publisher'"
  echo "      $JENKINS_URL -> New Item -> Pipeline -> '$JOB_NAME' -> Definition: Pipeline script -> paste ./Jenkinsfile -> Save -> Build Now"
  echo "      (Script Console, to see charts in the report: System.setProperty(\"hudson.model.DirectoryBrowserSupport.CSP\", \"\"))"
fi
echo "The test runs about 10 minutes: ramp-up 120 s, then steady state up to 600 s in total."
echo "Do not run it at the same time as the JMeter / Lighthouse jobs - they load the same app and the same machine."
