def call(String service) {
    pipeline {
        agent none
        options {
            disableConcurrentBuilds()
        }
        parameters {
            booleanParam(name: 'DEPLOY', defaultValue: false, description: 'main 빌드 성공 후 시연 클러스터 배포')
        }
        stages {
            stage('Test and build') {
                agent { label 'erp-ci-db' }
                options { timeout(time: 20, unit: 'MINUTES') }
                steps {
                    withEnv(["ERP_SERVICE=${service}"]) {
                        sh(script: libraryResource('erp/db-build.sh'))
                    }
                }
            }
            stage('Deploy to development') {
                when {
                    beforeAgent true
                    allOf {
                        branch 'main'
                        expression { env.DEV_INSTANCE_ID?.trim() }
                    }
                }
                agent { label 'erp-ci-db' }
                options { timeout(time: 20, unit: 'MINUTES') }
                steps {
                    withEnv(["ERP_SERVICE=${service}"]) {
                        sh(script: libraryResource('erp/deploy-dev.sh'))
                    }
                }
            }
            stage('Publish and deploy') {
                when {
                    beforeAgent true
                    allOf {
                        branch 'main'
                        expression { params.DEPLOY }
                    }
                }
                agent { label 'erp-docker' }
                options { timeout(time: 20, unit: 'MINUTES') }
                steps {
                    script {
                        env.LOCAL_IMAGE = "${service}:ci-${env.GIT_COMMIT}-${env.BUILD_NUMBER}"
                    }
                    withEnv(["DEPLOYMENT_NAME=${service}", "CONTAINER_NAME=${service}"]) {
                        sh 'docker build -t "$LOCAL_IMAGE" .'
                        sh(script: libraryResource('erp/deploy-image.sh'))
                    }
                }
                post {
                    always {
                        sh 'if [ -n "${LOCAL_IMAGE:-}" ]; then docker image rm "$LOCAL_IMAGE" >/dev/null 2>&1 || true; fi'
                    }
                }
            }
        }
    }
}
