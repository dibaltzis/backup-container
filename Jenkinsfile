pipeline {
    agent { label 'fedora-docker' }

    environment {
        REGISTRY = '192.168.31.229:5444'
        IMAGE    = 'backup_runner'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build & Push') {
            steps {
                sh './build_push_multiarch.sh'
            }
        }
    }

    post {
        success {
            script {
                def shortCommit = env.GIT_COMMIT?.take(6) ?: 'unknown'
                echo "✅ Image pushed: ${REGISTRY}/${IMAGE}:${shortCommit}"
            }
        }

        failure {
            echo "❌ Build failed for ${IMAGE}"
        }
    }
}