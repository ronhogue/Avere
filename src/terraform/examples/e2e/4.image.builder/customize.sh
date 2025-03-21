#!/bin/bash -ex

binPaths=""
binDirectory="/usr/local/bin"
cd $binDirectory

storageContainerUrl="https://azrender.blob.core.windows.net/bin"
storageContainerSas="?sv=2021-04-10&st=2022-01-01T08%3A00%3A00Z&se=2222-12-31T08%3A00%3A00Z&sr=c&sp=r&sig=Q10Ob58%2F4hVJFXfV8SxJNPbGOkzy%2BxEaTd5sJm8BLk8%3D"

echo "Customize (Start): Image Build Platform"
yum -y install epel-release
yum -y install gcc gcc-c++
yum -y install nfs-utils
# yum -y install unzip
# yum -y install cmake
yum -y install git
yum -y install jq

versionInfo="3.25.1"
installFile="cmake-$versionInfo-linux-x86_64.tar.gz"
downloadUrl="$storageContainerUrl/CMake/$versionInfo/$installFile$storageContainerSas"
curl -o $installFile -L $downloadUrl
tar -xzf $installFile
installDirectory="cmake"
mv cmake-$versionInfo-linux-x86_64 $installDirectory
binPathCMake="$(pwd)/$installDirectory/bin"
binPaths="$binPaths:$binPathCMake"
echo "Customize (End): Image Build Platform"

echo "Customize (Start): Image Build Parameters"
buildConfig=$(echo $buildConfigEncoded | base64 -d)
machineType=$(echo $buildConfig | jq -r .machineType)
gpuPlatform=$(echo $buildConfig | jq -c .gpuPlatform)
renderManager=$(echo $buildConfig | jq -r .renderManager)
renderEngines=$(echo $buildConfig | jq -c .renderEngines)
adminUsername=$(echo $buildConfig | jq -r .adminUsername)
adminPassword=$(echo $buildConfig | jq -r .adminPassword)
echo "Machine Type: $machineType"
echo "GPU Platform: $gpuPlatform"
echo "Render Manager: $renderManager"
echo "Render Engines: $renderEngines"
echo "Customize (End): Image Build Parameters"

if [[ $gpuPlatform == *GRID* ]]; then
  echo "Customize (Start): NVIDIA GPU (GRID)"
  yum -y install kernel-devel-$(uname -r)
  yum -y install dkms
  installFile="nvidia-gpu-grid.run"
  downloadUrl="https://go.microsoft.com/fwlink/?linkid=874272"
  curl -o $installFile -L $downloadUrl
  chmod +x $installFile
  ./$installFile --silent --dkms 1> "nvidia-grid.output.txt" 2> "nvidia-grid.error.txt"
  echo "Customize (End): NVIDIA GPU (GRID)"
fi

if [[ $gpuPlatform == *CUDA* ]] || [[ $gpuPlatform == *CUDA.OptiX* ]]; then
  echo "Customize (Start): NVIDIA GPU (CUDA)"
  yum-config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/cuda-rhel7.repo
  yum -y install cuda 1> "nvidia-cuda.output.txt" 2> "nvidia-cuda.error.txt"
  echo "Customize (End): NVIDIA GPU (CUDA)"
fi

if [[ $gpuPlatform == *CUDA.OptiX* ]]; then
  echo "Customize (Start): NVIDIA GPU (OptiX)"
  versionInfo="7.6.0"
  installFile="NVIDIA-OptiX-SDK-$versionInfo-linux64-x86_64-31894579.sh"
  downloadUrl="$storageContainerUrl/NVIDIA/OptiX/$versionInfo/$installFile$storageContainerSas"
  curl -o $installFile -L $downloadUrl
  chmod +x $installFile
  installDirectory="nvidia-optix"
  mkdir $installDirectory
  ./$installFile --skip-license --prefix="$binDirectory/$installDirectory" 1> "nvidia-optix.output.txt" 2> "nvidia-optix.error.txt"
  yum -y install mesa-libGL-devel
  yum -y install libXrandr-devel
  yum -y install libXinerama-devel
  yum -y install libXcursor-devel
  buildDirectory="$binDirectory/$installDirectory/build"
  mkdir $buildDirectory
  $binPathCMake/cmake -B $buildDirectory -S "$binDirectory/$installDirectory/sdk" 1> "nvidia-optix-cmake.output.txt" 2> "nvidia-optix-cmake.error.txt"
  make -j -C $buildDirectory 1> "nvidia-optix-make.output.txt" 2> "nvidia-optix-make.error.txt"
  binPaths="$binPaths:$buildDirectory/bin"
  echo "Customize (End): NVIDIA GPU (OptiX)"
fi

if [ $machineType == "Scheduler" ]; then
  echo "Customize (Start): Azure CLI"
  azRepoPath="/etc/yum.repos.d/azure-cli.repo"
  echo "[azure-cli]" > $azRepoPath
  echo "name=Azure CLI" >> $azRepoPath
  echo "baseurl=https://packages.microsoft.com/yumrepos/azure-cli" >> $azRepoPath
  echo "enabled=1" >> $azRepoPath
  echo "gpgcheck=1" >> $azRepoPath
  echo "gpgkey=https://packages.microsoft.com/keys/microsoft.asc" >> $azRepoPath
  yum -y install azure-cli 1> "az-cli.output.txt" 2> "az-cli.error.txt"
  echo "Customize (End): Azure CLI"

  if [ $renderManager == "Deadline" ]; then
    echo "Customize (Start): NFS Server"
    systemctl --now enable nfs-server
    echo "Customize (End): NFS Server"
  fi

  echo "Customize (Start): CycleCloud"
  cycleCloudPath="/usr/local/cyclecloud"
  cycleCloudRepoPath="/etc/yum.repos.d/cyclecloud.repo"
  echo "[cyclecloud]" > $cycleCloudRepoPath
  echo "name=CycleCloud" >> $cycleCloudRepoPath
  echo "baseurl=https://packages.microsoft.com/yumrepos/cyclecloud" >> $cycleCloudRepoPath
  echo "gpgcheck=1" >> $cycleCloudRepoPath
  echo "gpgkey=https://packages.microsoft.com/keys/microsoft.asc" >> $cycleCloudRepoPath
  yum -y install java-1.8.0-openjdk
  JAVA_HOME=/bin/java
  yum -y install cyclecloud8
  binPaths="$binPaths:$cycleCloudPath/bin"
  cd /opt/cycle_server
  unzip -q ./tools/cyclecloud-cli.zip
  ./cyclecloud-cli-installer/install.sh --installdir $cycleCloudPath
  cd $binDirectory
  cycleCloudInitFile="cycle_initialize.json"
  echo "[" > $cycleCloudInitFile
  echo "{" >> $cycleCloudInitFile
  echo "\"AdType\": \"Application.Setting\"," >> $cycleCloudInitFile
  echo "\"Name\": \"cycleserver.installation.initial_user\"," >> $cycleCloudInitFile
  echo "\"Value\": \"$adminUsername\"" >> $cycleCloudInitFile
  echo "}," >> $cycleCloudInitFile
  echo "{" >> $cycleCloudInitFile
  echo "\"AdType\": \"Application.Setting\"," >> $cycleCloudInitFile
  echo "\"Name\": \"distribution_method\"," >> $cycleCloudInitFile
  echo "\"Category\": \"system\"," >> $cycleCloudInitFile
  echo "\"Status\": \"internal\"," >> $cycleCloudInitFile
  echo "\"Value\": \"manual\"" >> $cycleCloudInitFile
  echo "}," >> $cycleCloudInitFile
  echo "{" >> $cycleCloudInitFile
  echo "\"AdType\": \"Application.Setting\"," >> $cycleCloudInitFile
  echo "\"Name\": \"cycleserver.installation.complete\"," >> $cycleCloudInitFile
  echo "\"Value\": true" >> $cycleCloudInitFile
  echo "}," >> $cycleCloudInitFile
  echo "{" >> $cycleCloudInitFile
  echo "\"AdType\": \"AuthenticatedUser\"," >> $cycleCloudInitFile
  echo "\"Name\": \"$adminUsername\"," >> $cycleCloudInitFile
  echo "\"RawPassword\": \"$adminPassword\"," >> $cycleCloudInitFile
  echo "\"Superuser\": true" >> $cycleCloudInitFile
  echo "}" >> $cycleCloudInitFile
  echo "]" >> $cycleCloudInitFile
  mv $cycleCloudInitFile /opt/cycle_server/config/data/
  echo "Customize (End): CycleCloud"
fi

case $renderManager in
  "RoyalRender")
    schedulerVersion="8.4.03"
    ;;
  "Deadline")
    schedulerVersion="10.2.0.9"
    schedulerClientPath="/DeadlineClient"
    schedulerDatabaseHost=$(hostname)
    schedulerDatabasePath="/DeadlineDatabase"
    schedulerRepositoryPath="/DeadlineRepository"
    schedulerCertificateFile="Deadline10Client.pfx"
    schedulerRepositoryLocalMount="/mnt/scheduler"
    schedulerRepositoryCertificate="$schedulerRepositoryLocalMount/$schedulerCertificateFile"
    schedulerClientBinPath="$schedulerClientPath/bin"
    ;;
esac
binPaths="$binPaths:$schedulerClientBinPath"

rendererPathBlender="/usr/local/blender3"
rendererPathPBRT3="/usr/local/pbrt/v3"
rendererPathPBRT4="/usr/local/pbrt/v4"
rendererPathUnreal="/usr/local/unreal5"

if [[ $renderEngines == *Blender* ]]; then
  binPaths="$binPaths:$rendererPathBlender"
fi
if [[ $renderEngines == *Unreal* ]]; then
  binPaths="$binPaths:$rendererPathUnreal"
fi
echo "PATH=$PATH$binPaths" > /etc/profile.d/aaa.sh

case $renderManager in
  "RoyalRender")
    echo "Customize (Start): Royal Render Download"
    installFile="RoyalRender__${schedulerVersion}__installer.zip"
    downloadUrl="$storageContainerUrl/RoyalRender/$schedulerVersion/$installFile$storageContainerSas"
    curl -o $installFile -L $downloadUrl
    unzip -q $installFile
    echo "Customize (End): Royal Render Download"

    echo "Customize (Start): Royal Render Installer"
    yum -y install fontconfig
    yum -y install libXrender
    yum -y install libXext
    rootDirectory="RoyalRender"
    installFile="rrSetup_linux"
    installDirectory="RoyalRender__${schedulerVersion}__installer"
    chmod +x ./$installDirectory/$installFile
    mkdir $rootDirectory
    ./$installDirectory/$installFile -console -rrRoot $rootDirectory 1> "$rootDirectory.output.txt" 2> "$rootDirectory.error.txt"
    echo "Customize (End): Royal Render Installer"

    cd $rootDirectory
    export RR_ROOT=$(pwd)
    if [ $machineType == "Scheduler" ]; then
      echo "Customize (Start): Royal Render Server"
      # installFile="lx__rrServerconsole.sh"
      # ./$installFile 1> "rr-server.output.txt" 2> "rr-server.error.txt"

      echo "Customize (End): Royal Render Server"
    fi

    echo "Customize (Start): Royal Render Client"

    echo "Customize (End): Royal Render Client"
    cd $binDirectory
    ;;
  "Deadline")
    echo "Customize (Start): Deadline Download"
    installFile="Deadline-$schedulerVersion-linux-installers.tar"
    downloadUrl="$storageContainerUrl/Deadline/$schedulerVersion/$installFile$storageContainerSas"
    curl -o $installFile -L $downloadUrl
    tar -xzf $installFile
    echo "Customize (End): Deadline Download"

    if [ $machineType == "Scheduler" ]; then
      echo "Customize (Start): Deadline Repository"
      installFile="DeadlineRepository-$schedulerVersion-linux-x64-installer.run"
      ./$installFile --mode unattended --dbLicenseAcceptance accept --installmongodb true --dbhost $schedulerDatabaseHost --mongodir $schedulerDatabasePath --prefix $schedulerRepositoryPath
      mv /tmp/*_installer.log ./deadline-log-repository.txt
      cp $schedulerDatabasePath/certs/$schedulerCertificateFile $schedulerRepositoryPath/$schedulerCertificateFile
      chmod +r $schedulerRepositoryPath/$schedulerCertificateFile
      echo "$schedulerRepositoryPath *(rw,no_root_squash)" >> /etc/exports
      exportfs -a
      echo "Customize (End): Deadline Repository"
    fi

    echo "Customize (Start): Deadline Client"
    installFile="DeadlineClient-$schedulerVersion-linux-x64-installer.run"
    installArgs="--mode unattended --prefix $schedulerClientPath"
    if [ $machineType == "Scheduler" ]; then
      installArgs="$installArgs --slavestartup false --launcherdaemon false"
    else
      [ $machineType == "Farm" ] && workerStartup=true || workerStartup=false
      installArgs="$installArgs --slavestartup $workerStartup --launcherdaemon true"
    fi
    ./$installFile $installArgs
    mv /tmp/*_installer.log ./deadline-log-client.txt
    $schedulerClientBinPath/deadlinecommand -ChangeRepositorySkipValidation Direct $schedulerRepositoryLocalMount $schedulerRepositoryCertificate ""
    echo "Customize (End): Deadline Client"
    ;;
esac

if [[ $renderEngines == *Blender* ]]; then
  echo "Customize (Start): Blender"
  yum -y install libXi
  yum -y install libXxf86vm
  yum -y install libXfixes
  yum -y install libXrender
  yum -y install libGL
  versionInfo="3.3.1"
  installFile="blender-$versionInfo-linux-x64.tar.xz"
  downloadUrl="$storageContainerUrl/Blender/$versionInfo/$installFile$storageContainerSas"
  curl -o $installFile -L $downloadUrl
  tar -xJf $installFile
  mv blender-$versionInfo-linux-x64 $rendererPathBlender
  echo "Customize (End): Blender"
fi

if [[ $renderEngines == *PBRT* ]]; then
  echo "Customize (Start): PBRT v3"
  versionInfo="v3"
  git clone --recursive https://github.com/mmp/pbrt-$versionInfo.git 1> "pbrt-$versionInfo-git.output.txt" 2> "pbrt-$versionInfo-git.error.txt"
  mkdir -p $rendererPathPBRT3
  $binPathCMake/cmake -B $rendererPathPBRT3 -S $binDirectory/pbrt-$versionInfo 1> "pbrt-$versionInfo-cmake.output.txt" 2> "pbrt-$versionInfo-cmake.error.txt"
  make -j -C $rendererPathPBRT3 1> "pbrt-$versionInfo-make.output.txt" 2> "pbrt-$versionInfo-make.error.txt"
  ln -s $rendererPathPBRT3/pbrt /usr/bin/pbrt3
  echo "Customize (End): PBRT v3"

  echo "Customize (Start): PBRT v4"
  yum -y install mesa-libGL-devel
  yum -y install libXrandr-devel
  yum -y install libXinerama-devel
  yum -y install libXcursor-devel
  yum -y install libXi-devel
  versionInfo="v4"
  git clone --recursive https://github.com/mmp/pbrt-$versionInfo.git 1> "pbrt-$versionInfo-git.output.txt" 2> "pbrt-$versionInfo-git.error.txt"
  mkdir -p $rendererPathPBRT4
  $binPathCMake/cmake -B $rendererPathPBRT4 -S $binDirectory/pbrt-$versionInfo 1> "pbrt-$versionInfo-cmake.output.txt" 2> "pbrt-$versionInfo-cmake.error.txt"
  make -j -C $rendererPathPBRT4 1> "pbrt-$versionInfo-make.output.txt" 2> "pbrt-$versionInfo-make.error.txt"
  ln -s $rendererPathPBRT4/pbrt /usr/bin/pbrt4
  echo "Customize (End): PBRT v4"
fi

if [[ $renderEngines == *PBRT.Moana* ]]; then
  echo "Customize (Start): PBRT Data (Moana Island)"
  dataDirectory="moana"
  mkdir $dataDirectory
  installFile="island-basepackage-v1.1.tgz"
  downloadUrl="$storageContainerUrl/PBRT/$dataDirectory/$installFile$storageContainerSas"
  curl -o $installFile -L $downloadUrl
  tar -xzf $installFile -C $dataDirectory
  installFile="island-pbrt-v1.1.tgz"
  downloadUrl="$storageContainerUrl/PBRT/$dataDirectory/$installFile$storageContainerSas"
  curl -o $installFile -L $downloadUrl
  tar -xzf $installFile -C $dataDirectory
  installFile="island-pbrtV4-v2.0.tgz"
  downloadUrl="$storageContainerUrl/PBRT/$dataDirectory/$installFile$storageContainerSas"
  curl -o $installFile -L $downloadUrl
  tar -xzf $installFile -C $dataDirectory
  echo "Customize (End): PBRT Data (Moana Island)"
fi

if [[ $renderEngines == *Unity* ]]; then
  echo "Customize (Start): Unity Hub"
  unityRepoPath="/etc/yum.repos.d/unityhub.repo"
  echo "[unityhub]" > $unityRepoPath
  echo "name=Unity Hub" >> $unityRepoPath
  echo "baseurl=https://hub.unity3d.com/linux/repos/rpm/stable" >> $unityRepoPath
  echo "enabled=1" >> $unityRepoPath
  echo "gpgcheck=1" >> $unityRepoPath
  echo "gpgkey=https://hub.unity3d.com/linux/repos/rpm/stable/repodata/repomd.xml.key" >> $unityRepoPath
  echo "repo_gpgcheck=1" >> $unityRepoPath
  yum -y install unityhub
  echo "Customize (End): Unity Hub"
fi

if [[ $renderEngines == *Unreal* ]] || [[ $renderEngines == *Unreal.PixelStream* ]]; then
  echo "Customize (Start): Unreal Engine"
  yum -y install libicu
  versionInfo="5.1.0"
  installFile="UnrealEngine-$versionInfo-release.tar.gz"
  downloadUrl="$storageContainerUrl/Unreal/$versionInfo/$installFile$storageContainerSas"
  curl -o $installFile -L $downloadUrl
  tar -xzf $installFile
  mkdir $rendererPathUnreal
  mv UnrealEngine-$versionInfo-release $rendererPathUnreal
  $rendererPathUnreal/Setup.sh 1> "unreal-engine-setup.output.txt" 2> "unreal-engine-setup.error.txt"
  echo "Customize (End): Unreal Engine"

  if [ $machineType == "Workstation" ]; then
    echo "Customize (Start): Unreal Project Files"
    $rendererPathUnreal/GenerateProjectFiles.sh 1> "unreal-project-files-generate.output.txt" 2> "unreal-project-files-generate.error.txt"
    make -j -C $rendererPathUnreal 1> "unreal-project-files-make.output.txt" 2> "unreal-project-files-make.error.txt"
    echo "Customize (End): Unreal Project Files"
  fi

  if [[ $renderEngines == *Unreal.PixelStream* ]]; then
    echo "Customize (Start): Unreal Pixel Streaming"
    git clone --recursive https://github.com/EpicGames/PixelStreamingInfrastructure 1> "unreal-stream-git.output.txt" 2> "unreal-stream-git.error.txt"
    installFile="PixelStreamingInfrastructure/SignallingWebServer/platform_scripts/bash/setup.sh"
    chmod +x $installFile
    ./$installFile 1> "unreal-stream-signalling.output.txt" 2> "unreal-stream-signalling.error.txt"
    installFile="PixelStreamingInfrastructure/Matchmaker/platform_scripts/bash/setup.sh"
    chmod +x $installFile
    ./$installFile 1> "unreal-stream-matchmaker.output.txt" 2> "unreal-stream-matchmaker.error.txt"
    echo "Customize (End): Unreal Pixel Streaming"
  fi
fi

if [ $machineType == "Farm" ]; then
  if [ -f /tmp/onTerminate.sh ]; then
    echo "Customize (Start): CycleCloud Event Handler"
    mkdir -p /opt/cycle/jetpack/scripts
    cp /tmp/onTerminate.sh /opt/cycle/jetpack/scripts/onPreempt.sh
    cp /tmp/onTerminate.sh /opt/cycle/jetpack/scripts/onTerminate.sh
    echo "Customize (End): CycleCloud Event Handler"
  fi
fi

if [ $machineType == "Workstation" ]; then
  echo "Customize (Start): Desktop Environment"
  yum -y groups install "KDE Plasma Workspaces" 1> "kde.output.txt" 2> "kde.error.txt"
  echo "Customize (End): Desktop Environment"

  echo "Customize (Start): Teradici PCoIP"
  versionInfo="22.09.2"
  installFile="pcoip-agent-offline-centos7.9_$versionInfo-1.el7.x86_64.tar.gz"
  downloadUrl="$storageContainerUrl/Teradici/$versionInfo/$installFile$storageContainerSas"
  curl -o $installFile -L $downloadUrl
  installDirectory="pcoip-agent"
  mkdir $installDirectory
  tar -xzf $installFile -C $installDirectory
  cd $installDirectory
  ./install-pcoip-agent.sh pcoip-agent-graphics usb-vhci 1> "$installDirectory.output.txt" 2> "$installDirectory.error.txt"
  cd $binDirectory
  echo "Customize (End): Teradici PCoIP"
fi
