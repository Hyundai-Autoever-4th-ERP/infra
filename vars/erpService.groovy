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
                agent { label 'erp-java25' }
                options { timeout(time: 20, unit: 'MINUTES') }
                steps {
                    sh './gradlew --no-daemon clean build'
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
