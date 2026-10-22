
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    parameters {
        choice(
            name: 'RELEASE_MODE',
            choices: ['STABLE', 'FAULTY'],
            description: 'FAULTY deliberately removes health.html to test automatic rollback.'
        )
        booleanParam(
            name: 'DEPLOY_TO_K8S',
            defaultValue: true,
            description: 'Build and push the image, then deploy to Kubernetes.'
        )
    }

    environment {
        IMAGE_NAME = 'dhan01/disaster-response-portal'
    }

    stages {
        stage('Checkout Source') {
            steps {
                checkout scm
                bat 'git log -1 --oneline'
                bat 'dir'
            }
        }

        stage('Parallel Quality Checks') {
            parallel {
                stage('Incident Data Test') {
                    steps {
                        bat 'findstr /C:"INC-101" index.html >nul'
                        bat 'findstr /C:"INC-105" index.html >nul'
                        bat 'echo PASS: Incident records are present'
                    }
                }

                stage('Deployment Configuration Test') {
                    steps {
                        bat 'findstr /C:"readinessProbe" deployment.yaml >nul'
                        bat 'findstr /C:"health.html" deployment.yaml >nul'
                        bat 'findstr /C:"replicas: 2" deployment.yaml >nul'
                        bat 'echo PASS: Kubernetes health check and replicas configured'
                    }
                }

                stage('Required Files Test') {
                    steps {
                        bat 'if not exist index.html exit /b 1'
                        bat 'if not exist Dockerfile exit /b 1'
                        bat 'if not exist Jenkinsfile exit /b 1'
                        bat 'if not exist deployment.yaml exit /b 1'
                        bat 'if not exist health.html exit /b 1'
                        bat 'echo PASS: All required files are present'
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                bat 'docker version'
                bat 'docker build --build-arg RELEASE_MODE=%RELEASE_MODE% -t %IMAGE_NAME%:%BUILD_NUMBER%-%RELEASE_MODE% .'
            }
        }

        stage('Test Docker Image') {
            steps {
                script {
                    def tag = "${env.BUILD_NUMBER}-${params.RELEASE_MODE}"
                    def cname = "disaster-portal-test-${env.BUILD_NUMBER}"
                    try {
                        bat "docker run -d --name ${cname} -p 18080:80 ${env.IMAGE_NAME}:${tag}"
                        bat 'powershell -NoProfile -Command "$r = Invoke-WebRequest -UseBasicParsing http://localhost:18080/; if ($r.StatusCode -ne 200) { exit 1 }"'

                        if (params.RELEASE_MODE == 'STABLE') {
                            bat 'powershell -NoProfile -Command "$r = Invoke-WebRequest -UseBasicParsing http://localhost:18080/health.html; if ($r.StatusCode -ne 200) { exit 1 }"'
                        } else {
                            bat 'powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing http://localhost:18080/health.html; exit 1 } catch { if ($_.Exception.Response.StatusCode.value__ -eq 404) { exit 0 }; exit 1 }"'
                        }

                        echo "Docker HTTP tests passed for ${tag}"
                    } finally {
                        bat "docker rm -f ${cname}"
                    }
                }
            }
        }

        stage('Push to Docker Hub') {
            when {
                expression { return params.DEPLOY_TO_K8S }
            }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub',
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {
                    bat 'echo %DOCKER_PASSWORD% | docker login -u %DOCKER_USERNAME% --password-stdin'
                    bat 'docker push %IMAGE_NAME%:%BUILD_NUMBER%-%RELEASE_MODE%'
                    bat 'docker logout'
                }
            }
        }

        stage('Deploy and Verify Kubernetes') {
            when {
                expression { return params.DEPLOY_TO_K8S }
            }
            steps {
                script {
                    def tag = "${env.BUILD_NUMBER}-${params.RELEASE_MODE}"
                    def image = "${env.IMAGE_NAME}:${tag}"

                    withCredentials([
                        file(
                            credentialsId: 'kuberconfig',
                            variable: 'KUBECONFIG_FILE'
                        )
                    ]) {
                        try {
                            bat 'set KUBECONFIG=%KUBECONFIG_FILE%&& kubectl get nodes'
                            bat 'set KUBECONFIG=%KUBECONFIG_FILE%&& kubectl apply -f deployment.yaml'

                            bat "set KUBECONFIG=%KUBECONFIG_FILE%&& kubectl set image deployment/disaster-response-portal portal=${image}"

                            bat 'set KUBECONFIG=%KUBECONFIG_FILE%&& kubectl rollout status deployment/disaster-response-portal --timeout=100s'

                            bat 'set KUBECONFIG=%KUBECONFIG_FILE%&& kubectl get deployments,pods,services'
                            bat 'powershell -NoProfile -Command "$r = Invoke-WebRequest -UseBasicParsing http://localhost:30080/; if ($r.StatusCode -ne 200) { exit 1 }"'

                            echo "Deployment and HTTP verification succeeded for ${image}"
                        } catch (err) {
                            echo "Deployment verification failed. Inspecting the rollout and attempting automatic rollback."
                            bat 'set KUBECONFIG=%KUBECONFIG_FILE%&& kubectl get pods'
                            bat 'set KUBECONFIG=%KUBECONFIG_FILE%&& kubectl rollout history deployment/disaster-response-portal'

                            bat 'set KUBECONFIG=%KUBECONFIG_FILE%&& kubectl rollout undo deployment/disaster-response-portal'
                            bat 'set KUBECONFIG=%KUBECONFIG_FILE%&& kubectl rollout status deployment/disaster-response-portal --timeout=100s'

                            bat 'set KUBECONFIG=%KUBECONFIG_FILE%&& kubectl get deployment disaster-response-portal -o wide'
                            bat 'powershell -NoProfile -Command "$r = Invoke-WebRequest -UseBasicParsing http://localhost:30080/; if ($r.StatusCode -ne 200) { exit 1 }"'
                            bat 'powershell -NoProfile -Command "$r = Invoke-WebRequest -UseBasicParsing http://localhost:30080/health.html; if ($r.StatusCode -ne 200) { exit 1 }"'

                            echo 'Automatic rollback verified: the restored application responds successfully.'

                            if (params.RELEASE_MODE == 'FAULTY') {
                                currentBuild.result = 'UNSTABLE'
                                echo 'Expected faulty release was rejected and rolled back.'
                            } else {
                                throw err
                            }
                        }
                    }
                }
            }
        }

        stage('Archive Build Artifacts') {
            steps {
                archiveArtifacts(
                    artifacts: 'index.html,Dockerfile,Jenkinsfile,deployment.yaml,health.html',
                    fingerprint: true
                )
            }
        }
    }

    post {
        always {
            echo "Build ${env.BUILD_NUMBER} completed with result: ${currentBuild.currentResult}"
        }
    }
}
