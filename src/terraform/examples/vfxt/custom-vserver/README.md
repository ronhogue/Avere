# Avere vFXT with 1 Filer

This examples configures a render network, controller, and vfxt with 1 filer and demonstrates the ability to specify a vserver range used by the vFXT as shown in the diagram below:

![The architecture](../../../../../docs/images/terraform/1filer-custom-vserver.png)

The advantage of specifying a well-known IP range is that it enables you to setup the DNS entries ahead of time.

## Deployment Instructions

To run the example, execute the following instructions.  This assumes use of Azure Cloud Shell, but you can use in your own environment, ensure you install the vfxt provider as described in the [build provider instructions](../../../providers/terraform-provider-avere#build-the-terraform-provider-binary).  However, if you are installing into your own environment, you will need to follow the [instructions to setup terraform for the Azure environment](https://docs.microsoft.com/en-us/azure/terraform/terraform-install-configure).

1. browse to https://shell.azure.com

2. Specify your subscription by running this command with your subscription ID:  ```az account set --subscription YOUR_SUBSCRIPTION_ID```.  You will need to run this every time after restarting your shell, otherwise it may default you to the wrong subscription, and you will see an error similar to `azurerm_public_ip.vm is empty tuple`.

3. double check your Avere vFXT prerequisites, including running `az vm image terms accept --urn microsoft-avere:vfxt:avere-vfxt-controller:latest`: https://docs.microsoft.com/en-us/azure/avere-vfxt/avere-vfxt-prereqs

4. If not already installed, run the following commands to install the Avere vFXT provider for Azure:
```bash
version=$(curl -s https://api.github.com/repos/Azure/Avere/releases/latest | jq -r .tag_name | sed -e 's/[^0-9]*\([0-9].*\)$/\1/')
browser_download_url=$(curl -s https://api.github.com/repos/Azure/Avere/releases/latest | jq -r .assets[].browser_download_url | grep -e "terraform-provider-avere$")
mkdir -p ~/.terraform.d/plugins/registry.terraform.io/hashicorp/avere/$version/linux_amd64
wget -O ~/.terraform.d/plugins/registry.terraform.io/hashicorp/avere/$version/linux_amd64/terraform-provider-avere_v$version $browser_download_url
chmod 755 ~/.terraform.d/plugins/registry.terraform.io/hashicorp/avere/$version/linux_amd64/terraform-provider-avere_v$version
```

5. get the terraform examples
```bash
mkdir tf
cd tf
git init
git remote add origin -f https://github.com/Azure/Avere.git
git config core.sparsecheckout true
echo "src/terraform/*" >> .git/info/sparse-checkout
git pull origin main
```

6. `cd src/terraform/examples/vfxt/custom-vserver`

7. `code main.tf` to edit the local variables section at the top of the file, to customize to your preferences.  If you are using an [ssk key](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/mac-create-ssh-keys), ensure that ~/.ssh/id_rsa is populated.

8. execute `terraform init` in the directory of `main.tf`.

9. execute `terraform apply -auto-approve` to build the vfxt cluster

Once installed you will be able to login and use the vFXT cluster according to the vFXT documentation: https://docs.microsoft.com/en-us/azure/avere-vfxt/avere-vfxt-cluster-gui.

Try to scale up and down the cluster, adjust the customer settings, add new junctions, etc, by editing the `main.tf`, and running `terraform apply -auto-approve`.

When you are done using the cluster, you can destroy it by running `terraform destroy -auto-approve` or just delete the three resource groups created.