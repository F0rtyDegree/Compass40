# План работ: GPS-стабилизация

1.  **Создать `lib/utils/bearing_calculator.dart`:**
    *   Реализовать в нем статическую функцию для вычисления пеленга (направления) по двум географическим точкам.

2.  **Создать `lib/providers/stabilized_compass_provider.dart`:**
    *   Класс `StabilizedCompassProvider` должен быть `ChangeNotifier`.
    *   Подписаться на потоки данных от `my_compass` и `gps_info`.
    *   Хранить состояния: `magneticHeading`, `gpsBearing`, `currentSpeed`.
    *   Реализовать логику: при достаточной скорости, вычислять `gpsBearing` с помощью `BearingCalculator`.
    *   Создать геттер `stabilizedHeading`, который возвращает `magneticHeading` (если стоим) или `gpsBearing` (если движемся).

3.  **Интегрировать в приложение:**
    *   Зарегистрировать `StabilizedCompassProvider` в `main.dart`.
    *   На экране компаса (`CompassScreen`) использовать `stabilizedHeading` из нового провайдера для анимации стрелки.

### Следующее действие

*   Начать с **пункта 1**: Создание `lib/utils/bearing_calculator.dart`.
