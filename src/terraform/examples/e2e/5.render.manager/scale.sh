#!/bin/bash -ex

az login --identity

queuedTasks=0
activeJobIds=$(deadlinecommand -GetJobIdsFilter Status=Active)
for jobId in $(echo $activeJobIds); do
    jobDetails=$(deadlinecommand -GetJobDetails $jobId)
    jobProperty="SubmitDate="
    jobSubmitDate=$(echo "$jobDetails" | grep $jobProperty)
    jobSubmitDate=$(echo $${jobSubmitDate#$jobProperty})
    jobWaitSecondsStart=$(date -u +%s --date="$jobSubmitDate")
    jobWaitSecondsEnd=$(date -u +%s)
    jobWaitSeconds=$(($jobWaitSecondsEnd-$jobWaitSecondsStart))
    if [ $jobWaitSeconds -gt $jobWaitThresholdSeconds ]; then
      taskIds=$(deadlinecommand -GetJobTaskIds $jobId)
      for taskId in $(echo $taskIds); do
        task=$(deadlinecommand -GetJobTask $jobId $taskId)
        taskProperty="TaskStatus="
        taskStatus=$(echo "$task" | grep $taskProperty)
        taskStatus=$(echo $${taskStatus#$taskProperty})
        if [ $taskStatus == "Queued" ]; then
          ((queuedTasks++))
        fi
      done
    fi
done

if [ $queuedTasks -gt 0 ]; then # Scale Up
  nodeCount=$(az vmss show --resource-group $resourceGroupName --name $scaleSetName --query "sku.capacity")
  nodeCount=$(($nodeCount + $queuedTasks))
  az vmss scale --resource-group $resourceGroupName --name $scaleSetName --new-capacity $nodeCount
else # Scale Down
  workerNames=$(deadlinecommand -GetSlaveNames)
  for workerName in $(echo $workerNames); do
    workerState=$(deadlinecommand -GetSlaveInfo $workerName SlaveState)
    if [ $workerState == "Idle" ]; then
      worker=$(deadlinecommand -GetSlave $workerName)
      workerProperty="WorkerLastRenderFinishedTime="
      workerIdleStartTime=$(echo "$worker" | grep $workerProperty)
      workerIdleStartTime=$(echo $${workerIdleStartTime#$workerProperty})
      if [ "$workerIdleStartTime" != "" ]; then
        workerIdleSecondsStart=$(date -u +%s --date="$workerIdleStartTime")
        workerIdleSecondsEnd=$(date -u +%s)
        workerIdleSeconds=$(($workerIdleSecondsEnd-$workerIdleSecondsStart))
      else
        workerIdleSeconds=$(deadlinecommand -GetSlaveInfo $workerName UpTimeSeconds)
      fi
      if [ $workerIdleSeconds -gt $workerIdleDeleteSeconds ]; then
        instanceId=$(az vmss list-instances --resource-group $resourceGroupName --name $scaleSetName --query "[?osProfile.computerName=='$workerName'].instanceId" --output tsv)
        az vmss delete-instances --resource-group $resourceGroupName --name $scaleSetName --instance-ids $instanceId
      fi
    fi
  done
fi
