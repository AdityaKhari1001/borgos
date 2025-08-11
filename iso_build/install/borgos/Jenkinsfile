// Jenkins Pipeline for BorgOS

pipeline {
    agent any
    
    environment {
        DOCKER_REGISTRY = 'docker.io'
        DOCKER_CREDENTIALS = credentials('docker-hub-credentials')
        DASHBOARD_IMAGE = 'borgos/dashboard'
        WEBSITE_IMAGE = 'borgos/website'
        KUBECONFIG = credentials('kubeconfig')
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
                    env.GIT_BRANCH = sh(returnStdout: true, script: 'git rev-parse --abbrev-ref HEAD').trim()
                }
            }
        }
        
        stage('Test') {
            parallel {
                stage('Python Tests') {
                    agent {
                        docker {
                            image 'python:3.11-slim'
                            args '-v /tmp:/tmp'
                        }
                    }
                    steps {
                        sh '''
                            pip install -r webui/requirements_dashboard.txt
                            pip install pytest pytest-cov flake8
                            flake8 webui/ --max-line-length=120 --ignore=E501,W503
                            pytest tests/ --cov=webui --cov-report=xml
                        '''
                        publishCoverage adapters: [coberturaAdapter('coverage.xml')]
                    }
                }
                
                stage('Security Scan') {
                    agent {
                        docker {
                            image 'aquasec/trivy:latest'
                            args '--entrypoint=""'
                        }
                    }
                    steps {
                        sh 'trivy fs --no-progress --security-checks vuln,config .'
                    }
                }
            }
        }
        
        stage('Build Docker Images') {
            parallel {
                stage('Build Dashboard') {
                    steps {
                        script {
                            docker.build("${DASHBOARD_IMAGE}:${env.GIT_COMMIT}", "-f Dockerfile.dashboard .")
                        }
                    }
                }
                
                stage('Build Website') {
                    steps {
                        script {
                            docker.build("${WEBSITE_IMAGE}:${env.GIT_COMMIT}", "-f Dockerfile.website .")
                        }
                    }
                }
            }
        }
        
        stage('Push to Registry') {
            when {
                anyOf {
                    branch 'main'
                    branch 'develop'
                    tag pattern: "v\\d+\\.\\d+\\.\\d+", comparator: "REGEXP"
                }
            }
            steps {
                script {
                    docker.withRegistry("https://${DOCKER_REGISTRY}", 'docker-hub-credentials') {
                        docker.image("${DASHBOARD_IMAGE}:${env.GIT_COMMIT}").push()
                        docker.image("${DASHBOARD_IMAGE}:${env.GIT_COMMIT}").push('latest')
                        docker.image("${WEBSITE_IMAGE}:${env.GIT_COMMIT}").push()
                        docker.image("${WEBSITE_IMAGE}:${env.GIT_COMMIT}").push('latest')
                    }
                }
            }
        }
        
        stage('Deploy to Staging') {
            when {
                branch 'develop'
            }
            steps {
                script {
                    sh '''
                        kubectl --kubeconfig=$KUBECONFIG apply -f k8s/ -n borgos-staging
                        kubectl --kubeconfig=$KUBECONFIG set image deployment/borgos-dashboard dashboard=${DASHBOARD_IMAGE}:${GIT_COMMIT} -n borgos-staging
                        kubectl --kubeconfig=$KUBECONFIG set image deployment/borgos-website website=${WEBSITE_IMAGE}:${GIT_COMMIT} -n borgos-staging
                        kubectl --kubeconfig=$KUBECONFIG rollout status deployment/borgos-dashboard -n borgos-staging
                        kubectl --kubeconfig=$KUBECONFIG rollout status deployment/borgos-website -n borgos-staging
                    '''
                }
            }
        }
        
        stage('Deploy to Production') {
            when {
                tag pattern: "v\\d+\\.\\d+\\.\\d+", comparator: "REGEXP"
            }
            input {
                message 'Deploy to production?'
                ok 'Deploy'
                parameters {
                    choice(name: 'DEPLOYMENT_TYPE', choices: ['Blue-Green', 'Canary', 'Rolling'], description: 'Deployment strategy')
                }
            }
            steps {
                script {
                    if (params.DEPLOYMENT_TYPE == 'Blue-Green') {
                        sh 'echo "Performing Blue-Green deployment..."'
                        // Blue-Green deployment logic
                    } else if (params.DEPLOYMENT_TYPE == 'Canary') {
                        sh 'echo "Performing Canary deployment..."'
                        // Canary deployment logic
                    } else {
                        sh '''
                            kubectl --kubeconfig=$KUBECONFIG apply -f k8s/ -n borgos
                            kubectl --kubeconfig=$KUBECONFIG set image deployment/borgos-dashboard dashboard=${DASHBOARD_IMAGE}:${GIT_COMMIT} -n borgos
                            kubectl --kubeconfig=$KUBECONFIG set image deployment/borgos-website website=${WEBSITE_IMAGE}:${GIT_COMMIT} -n borgos
                            kubectl --kubeconfig=$KUBECONFIG rollout status deployment/borgos-dashboard -n borgos
                            kubectl --kubeconfig=$KUBECONFIG rollout status deployment/borgos-website -n borgos
                        '''
                    }
                }
            }
        }
        
        stage('Smoke Tests') {
            when {
                anyOf {
                    branch 'main'
                    branch 'develop'
                }
            }
            steps {
                script {
                    sh '''
                        # Test dashboard endpoint
                        curl -f http://dashboard.borgos.ai/health || exit 1
                        
                        # Test website endpoint
                        curl -f http://borgos.ai || exit 1
                        
                        # Test Ollama API
                        curl -f http://api.borgos.ai/ollama/api/tags || exit 1
                    '''
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
        success {
            echo 'Pipeline completed successfully!'
            slackSend(
                color: 'good',
                message: "BorgOS deployment successful: ${env.JOB_NAME} - ${env.BUILD_NUMBER}"
            )
        }
        failure {
            echo 'Pipeline failed!'
            slackSend(
                color: 'danger',
                message: "BorgOS deployment failed: ${env.JOB_NAME} - ${env.BUILD_NUMBER}"
            )
        }
    }
}