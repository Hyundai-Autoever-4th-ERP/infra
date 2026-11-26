pipeline {
    agent { label 'erp-docker' }
    options {
        disableConcurrentBuilds()
        timeout(time: 20, unit: 'MINUTES')
    }
    parameters {
        booleanParam(name: 'DEPLOY', defaultValue: false, description: 'main 빌드를 ECR에 올리고 시연 클러스터의 기존 Gateway를 갱신')
    }
    stages {
        stage('Build') {
            steps {
                script {
                    env.LOCAL_IMAGE = "erp-gateway:ci-${env.GIT_COMMIT}-${env.BUILD_NUMBER}"
                }
                sh 'docker compose config --quiet'
                sh 'docker build -f api-gateway/Dockerfile -t "$LOCAL_IMAGE" .'
            }
        }
        stage('Gateway health') {
            steps {
                sh './ci/check-gateway.sh "$LOCAL_IMAGE"'
            }
        }
        stage('Publish and deploy') {
            when { allOf { branch 'main'; expression { params.DEPLOY } } }
            steps {
                withEnv(['DEPLOYMENT_NAME=api-gateway', 'CONTAINER_NAME=api-gateway']) {
                        sh 'sh resources/erp/deploy-image.sh'
                    }
            }
        }
    }
    post {
        always {
            sh 'if [ -n "${LOCAL_IMAGE:-}" ]; then docker image rm "$LOCAL_IMAGE" >/dev/null 2>&1 || true; fi'
        }
    }
}
