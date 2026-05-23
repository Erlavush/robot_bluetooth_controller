String bluetoothPayloadForCommand(String command) {
  if (command.endsWith('\n')) {
    return command;
  }
  return '$command\n';
}
