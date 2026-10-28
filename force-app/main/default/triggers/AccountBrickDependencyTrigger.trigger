trigger AccountBrickDependencyTrigger on Account (before insert, before update) {
  AccountBrickDependency.apply(Trigger.new, Trigger.oldMap);
}