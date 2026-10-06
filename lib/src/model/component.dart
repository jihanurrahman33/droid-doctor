/// A versioned piece of the Android build toolchain.
enum Component {
  java('JDK', 'Java (JDK)'),
  gradle('Gradle', 'Gradle'),
  agp('AGP', 'Android Gradle Plugin'),
  kgp('KGP', 'Kotlin Gradle Plugin');

  const Component(this.shortName, this.displayName);

  final String shortName;
  final String displayName;

  static Component parse(String name) => values.firstWhere(
        (c) => c.name == name,
        orElse: () => throw FormatException('Unknown component', name),
      );
}
