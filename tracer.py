"""Tracer code to suss things out."""


class ShipState(object):
    """Defines state of ship."""
    def __init__(self):
        """Create ship."""
        self.component_map = {}


class Component(object):
    """Generic component object.

    Can be connected to other components and propagate signals.
    """
    def __init__(self, obj_id):
        """Constructor."""
        self.connected_component_set = set()
        self.obj_id = obj_id

    def connect(self, other_component):
        """Connect other component to this component."""
        other_component.connected_component_set.add(self)

    def signal(self, data):
        """Signal this component with data."""
        print(f'{self.obj_id} got {data}')
        for connected_component in self.connected_component_set:
            connected_component.signal(data)


class PowerConduit(Component):
    """Used to transfer power."""
    def __init__(self, obj_id):
        """Constructor."""
        super().__init__(obj_id)


class Reactor(Component):
    """Used to generate power."""
    def __init__(self, obj_id):
        """Constructor."""
        super().__init__(obj_id)

    def get_power(self):
        return 0


def main():
    """Entry point."""
    conduit_list = []
    for obj_id in range(10):
        conduit = PowerConduit(obj_id)
        if conduit_list:
            conduit.connect(conduit_list[-1])
        conduit_list.append(conduit)

    reactor = Reactor(-1)
    conduit_list[0].connect(reactor)

    conduit_list[0].signal('test')
    conduit_list[-1].signal('test')


if __name__ == '__main__':
    main()