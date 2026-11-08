FROM jenkins/jenkins:lts-jdk17
ENV JAVA_OPTS="-Dhudson.security.csrf.GlobalCrumbIssuerConfiguration.DISABLE_CSRF_PROTECTION=true"
