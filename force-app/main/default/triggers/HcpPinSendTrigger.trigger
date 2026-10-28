trigger HcpPinSendTrigger on Hcp_Pin_Send__e (after insert) {
    ZetaHcpSignInService.deliver(Trigger.new);
}
