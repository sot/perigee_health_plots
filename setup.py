# Licensed under a 3-clause BSD style license - see LICENSE
import os
import sys
from setuptools import setup

try:
    from testr.setup_helper import cmdclass
except ImportError:
    cmdclass = {}


entry_points = {'console_scripts': [
    'perigee_health_plots_update=perigee_health_plots.pass_plots:main']}


if "--user" not in sys.argv:
    share_path = os.path.join(sys.prefix, "share", "perigee_health_plots")
    data_files = [(share_path, ['task_schedule.cfg'])]
else:
    data_files = None


setup(name='aca_hi_bgd',
      author='Jean Connelly, Tom Aldcroft',
      description='ACA perigee health plots',
      author_email='jconnelly@cfa.harvard.edu',
      setup_requires=['setuptools_scm', 'setuptools_scm_git_archive'],
      use_scm_version=True,
      zip_safe=False,
      packages=['perigee_health_plots'],
      package_data={'perigee_health_plots':
                    ['top_index_template.html',
                     'pass_idex_template.html',
                     'month_index_template.html']},
      tests_require=['pytest'],
      cmdclass=cmdclass,
      data_files=data_files,
      entry_points=entry_points,
      include_package_data=True,
      )
