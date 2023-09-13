#!/bin/bash -ex

source /etc/profile.d/aaa.sh

binDirectory="/usr/local/bin"
cd $binDirectory

serviceFile="aaaAutoScaler"
dataFilePath="/var/lib/waagent/ovf-env.xml"
dataFileText=$(xmllint --xpath "//*[local-name()='Environment']/*[local-name()='ProvisioningSection']/*[local-name()='LinuxProvisioningConfigurationSet']/*[local-name()='CustomData']/text()" $dataFilePath)
codeFilePath="$binDirectory/$serviceFile.sh"
echo $dataFileText | base64 -d > $codeFilePath
chmod +x $codeFilePath

serviceName="AAA Auto Scaler"
servicePath="/etc/systemd/system/$serviceFile.service"
echo "[Unit]" > $servicePath
echo "Description=$serviceName Service" >> $servicePath
echo "After=network-online.target" >> $servicePath
echo "" >> $servicePath
echo "[Service]" >> $servicePath
echo "Environment=resourceGroupName=${autoScale.resourceGroupName}" >> $servicePath
echo "Environment=scaleSetName=${autoScale.scaleSetName}" >> $servicePath
echo "Environment=scaleSetMachineCountMax=${autoScale.scaleSetMachineCountMax}" >> $servicePath
echo "Environment=jobWaitThresholdSeconds=${autoScale.jobWaitThresholdSeconds}" >> $servicePath
echo "Environment=workerIdleDeleteSeconds=${autoScale.workerIdleDeleteSeconds}" >> $servicePath
echo "ExecStart=/bin/bash $codeFilePath" >> $servicePath
echo "" >> $servicePath

timerPath="/etc/systemd/system/$serviceFile.timer"
echo "[Unit]" > $timerPath
echo "Description=$serviceName Timer" >> $timerPath
echo "" >> $timerPath
echo "[Timer]" >> $timerPath
echo "OnUnitActiveSec=${autoScale.detectionIntervalSeconds}" >> $timerPath
echo "AccuracySec=1us" >> $timerPath
echo "" >> $timerPath
echo "[Install]" >> $timerPath
echo "WantedBy=timers.target" >> $timerPath

if [ ${autoScale.enable} == true ]; then
  systemctl --now enable $serviceFile
fi
