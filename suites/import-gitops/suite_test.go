/*
Copyright © 2023 - 2024 SUSE LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package import_gitops

import (
	"context"
	"fmt"
	"strconv"
	"testing"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"github.com/rancher-sandbox/turtles-integration-suite-example/suites"
	appsv1 "k8s.io/api/apps/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/json"
	capiframework "sigs.k8s.io/cluster-api/test/framework"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	"github.com/rancher/turtles/test/e2e"
	"github.com/rancher/turtles/test/testenv"
)

// Test suite global vars.
var (
	// hostName is the host name for the Rancher Manager server.
	hostName string

	ctx = context.Background()

	setupClusterResult    *testenv.SetupTestClusterResult
	bootstrapClusterProxy capiframework.ClusterProxy
)

func TestE2E(t *testing.T) {
	RegisterFailHandler(Fail)

	ctrl.SetLogger(zap.New(zap.WriteTo(GinkgoWriter), zap.UseDevMode(true)))

	RunSpecs(t, "turtles-integration")
}

var _ = SynchronizedBeforeSuite(
	func() []byte {
		e2eConfig := e2e.LoadE2EConfig()
		By(fmt.Sprintf("Starting a %s management cluster",
			e2eConfig.GetVariableOrEmpty("MANAGEMENT_CLUSTER_ENVIRONMENT")))
		setupClusterResult = testenv.SetupTestCluster(ctx, testenv.SetupTestClusterInput{
			E2EConfig: e2eConfig,
			Scheme:    e2e.InitScheme(),
		})

		By("Deploying CertManager")
		testenv.DeployCertManager(ctx, testenv.DeployCertManagerInput{
			BootstrapClusterProxy: setupClusterResult.BootstrapClusterProxy,
		})

		By("Deploying Rancher Ingress")
		testenv.RancherDeployIngress(ctx, testenv.RancherDeployIngressInput{
			BootstrapClusterProxy:     setupClusterResult.BootstrapClusterProxy,
			CustomIngress:             e2e.NginxIngress,
			CustomIngressLoadBalancer: e2e.NginxIngressLoadBalancer,
			DefaultIngressClassPatch:  e2e.IngressClassPatch,
		})

		By("Deploying Rancher")
		rancherHookResult := testenv.DeployRancher(ctx, testenv.DeployRancherInput{
			BootstrapClusterProxy: setupClusterResult.BootstrapClusterProxy,
			RancherPatches:        [][]byte{suites.RancherSettingsPatch},
		})

		By("Waiting for Rancher to deploy Turtles")
		capiframework.WaitForDeploymentsAvailable(ctx, capiframework.WaitForDeploymentsAvailableInput{
			Getter: setupClusterResult.BootstrapClusterProxy.GetClient(),
			Deployment: &appsv1.Deployment{ObjectMeta: metav1.ObjectMeta{
				Name:      "rancher-turtles-controller-manager",
				Namespace: "cattle-turtles-system",
			}},
		}, e2eConfig.GetIntervals(setupClusterResult.BootstrapClusterProxy.GetName(), "wait-controllers")...)

		By("Deploying required CAPIProviders")
		testenv.CAPIOperatorDeployProvider(ctx, testenv.CAPIOperatorDeployProviderInput{
			BootstrapClusterProxy: setupClusterResult.BootstrapClusterProxy,
			CAPIProvidersYAML: [][]byte{
				suites.CAPIProviderDocker,
				suites.CAPIProviderKubeadm,
				suites.CAPIProviderRKE2,
			},
			WaitForDeployments: testenv.DefaultDeployments,
		})

		data, err := json.Marshal(e2e.Setup{
			ClusterName:     setupClusterResult.ClusterName,
			KubeconfigPath:  setupClusterResult.KubeconfigPath,
			RancherHostname: rancherHookResult.Hostname,
		})
		Expect(err).ToNot(HaveOccurred())
		return data
	},
	func(sharedData []byte) {
		setup := e2e.Setup{}
		Expect(json.Unmarshal(sharedData, &setup)).To(Succeed())

		hostName = setup.RancherHostname

		bootstrapClusterProxy = capiframework.NewClusterProxy(setup.ClusterName, setup.KubeconfigPath, e2e.InitScheme(), capiframework.WithMachineLogCollector(capiframework.DockerLogCollector{}))
		Expect(bootstrapClusterProxy).ToNot(BeNil(), "cluster proxy should not be nil")
	},
)

var _ = SynchronizedAfterSuite(
	func() {
	},
	func() {
		By("Dumping artifacts from the bootstrap cluster")
		testenv.DumpBootstrapCluster(ctx, bootstrapClusterProxy.GetKubeconfigPath())

		config := e2e.LoadE2EConfig()
		// skipping error check since it is already done at the beginning of the test in e2e.ValidateE2EConfig()
		skipCleanup, _ := strconv.ParseBool(config.GetVariableOrEmpty(e2e.SkipResourceCleanupVar))
		if skipCleanup {
			By(fmt.Sprintf("Skipping management Cluster %s cleanup", bootstrapClusterProxy.GetName()))
			return
		}

		testenv.CleanupTestCluster(ctx, testenv.CleanupTestClusterInput{
			SetupTestClusterResult: *setupClusterResult,
		})
	},
)
