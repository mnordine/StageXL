enum PowerPreference {
  normal('default'),
  lowPower('low-power'),
  highPerformance('high-performance');

  final String value;

  const PowerPreference(this.value);
}
