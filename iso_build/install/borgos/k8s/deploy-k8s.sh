#!/bin/bash

# BorgOS Kubernetes Deployment Script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="borgos"
KUBECTL="kubectl"

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  BorgOS Kubernetes Deployment${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

check_requirements() {
    echo -e "${BLUE}Checking requirements...${NC}"
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    print_status "kubectl installed"
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        echo "Please configure kubectl to connect to your cluster"
        exit 1
    fi
    print_status "Connected to Kubernetes cluster"
}

create_namespace() {
    echo -e "\n${BLUE}Creating namespace...${NC}"
    kubectl apply -f namespace.yaml
    print_status "Namespace created"
}

deploy_secrets() {
    echo -e "\n${BLUE}Deploying secrets and configs...${NC}"
    
    # Generate secure secret key if needed
    if grep -q "your-secret-key-here" secrets.yaml; then
        SECRET_KEY=$(openssl rand -hex 32)
        sed -i.bak "s/your-secret-key-here-change-in-production/$SECRET_KEY/g" secrets.yaml
        rm -f secrets.yaml.bak
        print_status "Generated secure secret key"
    fi
    
    kubectl apply -f secrets.yaml
    print_status "Secrets deployed"
}

deploy_storage() {
    echo -e "\n${BLUE}Creating storage volumes...${NC}"
    kubectl apply -f storage.yaml
    print_status "Storage volumes created"
}

deploy_services() {
    echo -e "\n${BLUE}Deploying services...${NC}"
    
    # Deploy Ollama
    kubectl apply -f ollama-deployment.yaml
    print_status "Ollama deployed"
    
    # Deploy Dashboard
    kubectl apply -f dashboard-deployment.yaml
    print_status "Dashboard deployed"
    
    # Deploy Website
    kubectl apply -f website-deployment.yaml
    print_status "Website deployed"
}

deploy_ingress() {
    echo -e "\n${BLUE}Configuring ingress...${NC}"
    kubectl apply -f ingress.yaml
    print_status "Ingress configured"
}

wait_for_pods() {
    echo -e "\n${BLUE}Waiting for pods to be ready...${NC}"
    
    echo "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/borgos-dashboard deployment/borgos-website \
        -n $NAMESPACE
    
    print_status "All deployments are ready"
}

get_status() {
    echo -e "\n${BLUE}Deployment Status:${NC}"
    kubectl get all -n $NAMESPACE
    
    echo -e "\n${BLUE}Ingress Status:${NC}"
    kubectl get ingress -n $NAMESPACE
}

get_access_info() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}  BorgOS Kubernetes Deployment Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    
    # Get ingress IP
    INGRESS_IP=$(kubectl get ingress borgos-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
    
    if [ "$INGRESS_IP" = "pending" ]; then
        echo -e "${YELLOW}Ingress IP is still being assigned...${NC}"
        echo -e "${YELLOW}Run 'kubectl get ingress -n borgos' to check status${NC}"
    else
        echo -e "${BLUE}Access Points:${NC}"
        echo -e "  Website:      ${GREEN}http://$INGRESS_IP${NC}"
        echo -e "  Dashboard:    ${GREEN}http://$INGRESS_IP:8080${NC}"
    fi
    
    echo
    echo -e "${BLUE}Port Forwarding (for local access):${NC}"
    echo -e "  Dashboard:    ${YELLOW}kubectl port-forward -n borgos svc/borgos-dashboard-service 8080:8080${NC}"
    echo -e "  Website:      ${YELLOW}kubectl port-forward -n borgos svc/borgos-website-service 8000:80${NC}"
    echo -e "  Ollama:       ${YELLOW}kubectl port-forward -n borgos svc/ollama-service 11434:11434${NC}"
    
    echo
    echo -e "${BLUE}Useful Commands:${NC}"
    echo -e "  View pods:    ${YELLOW}kubectl get pods -n borgos${NC}"
    echo -e "  View logs:    ${YELLOW}kubectl logs -n borgos [pod-name]${NC}"
    echo -e "  Scale:        ${YELLOW}kubectl scale deployment/borgos-dashboard --replicas=3 -n borgos${NC}"
    echo -e "  Delete all:   ${YELLOW}kubectl delete namespace borgos${NC}"
}

# Main execution
main() {
    print_header
    
    case "${1:-}" in
        --delete)
            echo -e "${RED}Deleting BorgOS from cluster...${NC}"
            kubectl delete namespace $NAMESPACE --ignore-not-found=true
            print_status "BorgOS removed from cluster"
            ;;
        --status)
            get_status
            ;;
        --port-forward)
            echo "Starting port forwarding..."
            kubectl port-forward -n $NAMESPACE svc/borgos-dashboard-service 8080:8080 &
            kubectl port-forward -n $NAMESPACE svc/borgos-website-service 8000:80 &
            echo "Dashboard: http://localhost:8080"
            echo "Website: http://localhost:8000"
            echo "Press Ctrl+C to stop"
            wait
            ;;
        *)
            check_requirements
            create_namespace
            deploy_secrets
            deploy_storage
            deploy_services
            deploy_ingress
            wait_for_pods
            get_status
            get_access_info
            ;;
    esac
}

# Change to script directory
cd "$(dirname "$0")"

# Run main function
main "$@"