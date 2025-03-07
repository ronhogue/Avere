# Backup any FXT or vFXT cluster and Restore to HPC Cache or Avere vFXT for Azure

This examples shows how to capture a backup of any FXT or vFXT cluster.  This backup can then be used to build Terraform for HPC Cache or Avere vFXT for Azure, and these files can be used to deploy to Azure, and fully automate deployment / teardown of the HPC Cache or Avere vFXT for Azure cluster.

## Instructions

1. copy the contents of the [config_restore.sh](https://raw.githubusercontent.com/Azure/Avere/main/src/terraform/examples/backuprestore/config_restore.sh) to your clipboard

2. ssh to the FXT or vFXT node using the following commands and paste in the contents from your clipboard:
```bash
# ssh to the vfxt node, using the admin password
ssh admin@VFXT_ADDRESS
# ssh to the root account, using the admin password
ssh root@localhost
# mark the file executable and past contents from your clipboard
mkdir -p /support/Backups/
vi /support/Backups/config_restore.sh 
chmod +x /support/Backups/config_restore.sh
```

3. run the `config_restore.sh` to generate the backup:
```bash
/support/Backups/config_restore.sh
```

4. once backup has run, zip up the directory:
```bash
tar zcvf backup.tgz /support/Backups/cluster_rebuild*
```

5. From the controller or other linux machine on the same VNET as the vFXT node, download the backup file:
```bash
scp admin@VFXT_ADDRESS:/support/Backups/backup.tgz .
```

6. From the controller node, download the Avere vFXT terraform provider that will be used to create the the terraform files `hpccache-main.tf` and `vfxt-main.tf` for the HPC Cache and Avere vFXT clusters respectively:
```bash
version=$(curl -s https://api.github.com/repos/Azure/Avere/releases/latest | jq -r .tag_name | sed -e 's/[^0-9]*\([0-9].*\)$/\1/')
browser_download_url=$(curl -s https://api.github.com/repos/Azure/Avere/releases/latest | jq -r .assets[].browser_download_url | grep -e "terraform-provider-avere$")
mkdir -p ~/.terraform.d/plugins/registry.terraform.io/hashicorp/avere/$version/linux_amd64
wget -O ~/.terraform.d/plugins/registry.terraform.io/hashicorp/avere/$version/linux_amd64/terraform-provider-avere_v$version $browser_download_url
chmod 755 ~/.terraform.d/plugins/registry.terraform.io/hashicorp/avere/$version/linux_amd64/terraform-provider-avere_v$version
```

7. generate the terraform files `hpccache-main.tf` and `vfxt-main.tf` for the HPC Cache and Avere vFXT clusters respectively:
```bash
mkdir -p ~/avere-restore
mv backup.tgz ~/avere-restore
cd ~/avere-restore
tar zxvf backup.tgz
# update the cluster rebuild path with the correct date before executing
~/.terraform.d/plugins/terraform-provider-avere cluster_rebuild_2020-05-04_17_30_00
```

8. You can now use the resulting terraform files `hpccache-main.tf` and `vfxt-main.tf` to deploy the clusters.  To learn how to deploy HPC Cache or vFXT clusters see the [Avere Terraform examples page](https://github.com/Azure/Avere/tree/main/src/terraform), and to learn the arguments see the [Avere vFXT provider page](https://github.com/Azure/Avere/tree/main/src/terraform/providers/terraform-provider-avere).
